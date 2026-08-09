# uwe5621ds: port to 5.15 / 6.2 / 6.12 + Bazel (DDK) build

## What changed

### Build system
- Added `BUILD.bazel` at the repo root defining two `ddk_module` targets,
  mirroring the two original kbuild Makefiles:
  - `uwe5621_bsp_sdio` (was `BSP/Makefile`, `CFG_AML_WIFI_DEVICE_UWE5621=y`)
  - `sprdwl_ng` (was `WIFI/Makefile`)
  `sprdwl_ng` depends on `uwe5621_bsp_sdio` (it calls symbols the BSP
  module `EXPORT_SYMBOL`s, e.g. `sprdwcn_bus_*`).
- Added `ddk_kconfig.uwe5621_bsp_sdio` and `ddk_kconfig.sprdwl_ng` — the
  minimal Kconfig fragments each `ddk_module` references via its
  `kconfig` attribute (modeled on the `rtl8733bs` example's single
  `ddk_kconfig` file).
- Added a top-level `Kconfig` with fuller `---help---` text for both
  symbols, for reference / non-Bazel integration.
- The original per-directory `Makefile`s and `Kconfig`s are left in place
  untouched, for reference and in case you still need a kbuild path for
  another vendor tree — they are not used by the Bazel build.
- **You will need to adjust**: the `load(...)` path at the top of
  `BUILD.bazel`, the `kernel_build = "//common_drivers:amlogic"` target
  name, and the `//common_drivers/...` deps, to match your actual kleaf
  workspace layout. These were inferred from the `rtl8733bs` example you
  provided; I don't have your kernel tree's `common_drivers` BUILD files
  to verify the exact target names.
- **Scope**: only the source files the original Makefiles actually
  select for `CFG_AML_WIFI_DEVICE_UWE5621=y` (SDIO, no GNSS/USB/PCIe) are
  in the `ddk_module` `srcs`. `BSP/boot`, `BSP/usb`, `BSP/pcie`,
  `BSP/sipc`, `BSP/tool`, `BSP/vm`, and `BSP/platform/gnss` are not part
  of that build and were left out (and *not* audited for 5.15+
  compatibility — see below).

### Source changes for kernel 5.15 / 6.2 / 6.12

This driver already carried `LINUX_VERSION_CODE` guards for a wide range
of older kernels (back to ~3.x), which meant most APIs that changed
*before* 5.15 (e.g. `kernel_read()`/`kernel_write()` signature,
`nla_parse()` argument count, `timer_setup()` vs `setup_timer()`,
`cfg80211_scan_done()`'s `struct cfg80211_scan_info` argument,
`struct timespec64` in a couple of cfg80211.c spots) were already
handled correctly and needed no changes.

The following APIs changed **after** the newest guard already in the
tree, and did need fixing. A new shared header,
`BSP/include/wcn_kcompat.h`, holds the small compatibility shims; each
change is also commented at its call site.

1. **`getnstimeofday()` / `struct timespec`** — removed in the 5.0
   y2038 cleanup. Replaced with `ktime_get_real_ts64()` /
   `struct timespec64` (and `timespec_to_ns()` →
   `timespec64_to_ns()`) throughout `BSP/sdio/*.c`, `BSP/sdio/sdiohal.h`,
   `WIFI/msg.c`, `WIFI/tx_msg.c`, `WIFI/wl_intf.c`, `WIFI/wl_core.h`.
   This affects performance/timing instrumentation only, not protocol
   logic, so the change is a straight type/API swap.

2. **`dev->dev_addr` became read-only** (kernel ~5.17). Direct
   `memcpy(dev->dev_addr, ...)` in `WIFI/main.c` was replaced with
   `eth_hw_addr_set()`. One call site (initial MAC assignment during
   `alloc_netdev()`) previously wrote through `ndev->dev_addr` from
   inside `sprdwl_set_mac_addr()`; that now writes into a local stack
   buffer which is committed with `eth_hw_addr_set()` afterward.

3. **`PDE_DATA()` → `pde_data()`** (renamed in kernel 5.17). Guarded via
   `wcn_pde_data()` in `wcn_kcompat.h`; used in `wcn_procfs.c`.

4. **`class_create()` dropped its `owner` argument** (kernel 6.4).
   Guarded via `wcn_class_create()` in `wcn_kcompat.h`; used in
   `wcn_log.c`.

5. **`.ndo_do_ioctl` stopped being called for `SIOCDEVPRIVATE` commands**
   (kernel 5.15). All of this driver's private ioctls
   (`SPRDWLIOCTL`/`SPRDWLGETSSID`/etc.) are in that range, so
   `sprdwl_ioctl()` in `WIFI/main.c` was moved from `.ndo_do_ioctl` to
   `.ndo_siocdevprivate` (new signature takes an extra
   `void __user *data`, unused since the handler already works off
   `struct ifreq`).

6. **`cfg80211_ops.mgmt_frame_register` → `.update_mgmt_frame_registrations`**
   (cfg80211 rework, kernel 5.8). This is the one substantive logic
   change, not just a rename: the old callback fired once per
   (de)registration; the new one hands the driver the *complete* desired
   bitmap on every call. `WIFI/cfg80211.c` now has
   `sprdwl_cfg80211_update_mgmt_frame_registrations()`, which diffs the
   new bitmap against the driver's own `vif->mgmt_reg` bitmap and
   replays the original per-subtype notification (via a shared
   `sprdwl_cfg80211_mgmt_frame_reg_one()` helper) for whichever bits
   actually changed. The pre-5.8 callback is kept, guarded, for
   completeness even though it's dead code at this floor.

7. **`netif_napi_add()` dropped its `weight` argument** (kernel 6.1).
   `WIFI/rx_msg.c` now picks between `netif_napi_add()` (< 6.1) and
   `netif_napi_add_weight()` (>= 6.1) to preserve the original weight of
   128.

## What I could **not** verify

I do not have your actual 5.15 / 6.2 / 6.12 kernel header trees, nor your
Amlogic kleaf/Bazel workspace (`common_drivers` and
`driver_modules/wifi_bt` `.bzl` files), available in this environment.
That means:

- **None of this has been compile-tested.** I audited the full buildable
  source set (50 files) against known kernel API history and fixed every
  break I could positively identify from that history, but I can't rule
  out something header-specific to your tree, or an API change I didn't
  think to check.
- The `BUILD.bazel` target names/paths for `kernel_build`,
  `//common_drivers:soc_headers`, and `//common_drivers/drivers/mmc/host:amlogic-mmc`
  are carried over from your `rtl8733bs` example on the assumption your
  workspace layout is shared between the two drivers. Verify these
  resolve in your tree.
- `genl_ops[].policy` is only set for `LINUX_VERSION_CODE < 5.2.0`
  (pre-existing code, not something I introduced) — on 5.2+ no per-op
  netlink attribute validation happens for the vendor generic-netlink
  family in `WIFI/npi.c`. This isn't a compile break, but you may want to
  add a `.policy` at the `genl_family` level if you want that validation
  back.
- `cfg80211_connect_result()`/`cfg80211_roamed()` (`WIFI/cfg80211.c`) are
  long-standing cfg80211 compatibility wrappers that I believe are still
  present through 6.12, but I could not confirm their exact current
  signatures against real headers.

## Build-log fixes applied

- **`BSP/usb/wcn_usb.h` not found.** `BSP/platform/wcn_boot.c` includes
  `usb_boot.h` *unconditionally* (not behind `#ifdef CONFIG_WCN_USB`),
  and `usb_boot.h` in turn does `#include "../usb/wcn_usb.h"`. Since
  `BSP/usb/*.c` isn't part of this SDIO build, that directory's headers
  weren't in the `ddk_headers` glob, so Bazel's sandbox never staged
  `wcn_usb.h` and the include failed. Fixed by adding `BSP/usb/*.h` (headers
  only, no `.c` sources) to `uwe5621_bsp_headers`'s `hdrs`/`linux_includes`.
  I re-swept every file in the buildable set for the same pattern
  (unguarded includes reaching into `BSP/boot`, `BSP/pcie`, `BSP/sipc`,
  `BSP/tool`, `BSP/vm`, `BSP/platform/gnss`); the only other two
  cross-directory reaches I found (`../fw/firmware_hex.h` and
  `../fw/usb_fdl.bin.hex`, both in `wcn_boot.c`) are properly behind
  `#ifdef CONFIG_WCN_DOWNLOAD_FIRMWARE_FROM_HEX` / `#ifdef CONFIG_WCN_USB`,
  neither of which this build defines, so they should be dead code paths
  and were left alone.

## Second build-log round (real 6.12 kleaf build)

- **`mm_segment_t`/`get_fs()`/`set_fs()`/`KERNEL_DS`** — this whole
  address-space-override API was removed in Linux 5.10. Two different
  usage patterns showed up:
  - **Pure file-stat pattern** (`BSP/platform/rdc_debug.c`, two call
    sites): `set_fs(KERNEL_DS)` wrapped around `vfs_stat()` just to let
    it accept a kernel-space path string. Replaced with a new
    `wcn_vfs_stat()` helper in `wcn_kcompat.h` built on `kern_path()` +
    `vfs_getattr()`, which take a kernel path directly and need no
    address-space override on any kernel version.
  - **Read/write-with-kernel-buffer pattern**
    (`WIFI/main.c` x2, `WIFI/npi.c`, `WIFI/rx_msg.c`,
    `WIFI/dbg_ini_util.c`): `set_fs(KERNEL_DS)` wrapped around
    `vfs_read()`/`vfs_write()` just to let them accept a kernel buffer.
    Replaced with `kernel_read()`/`kernel_write()`, which do that
    natively; the `get_fs()`/`set_fs()` pair was simply deleted.
    (`dbg_ini_util.c` already called `kernel_read()` — it only needed
    the dead `set_fs()`/`get_fs()` removed.)
  - One more occurrence, in `wcn_boot.c`'s
    `marlin_find_sdio_device_id()`, is behind
    `#ifdef CONFIG_WCN_CHECK_MODULE_VENDOR`, which this build never
    defines (it's commented out for every board variant in the
    original `BSP/Makefile`) — left untouched as dead code.

- **`filldir_t` return type is now `bool`, not `int`** (landed 5.1,
  well before our 5.15 floor). `find_callback()` in
  `BSP/platform/wcn_parn_parser.c` now returns `bool` (`true` = keep
  iterating, matching the old `return 0`); the pre-3.19 `void *ctx`
  fallback signature was dropped since it's unreachable at this floor.

- **`kzfree()` → `kfree_sensitive()`** (renamed in Linux 5.11). Fixed
  the one call site in `BSP/sdio/sdiohal_main.c`.

- **`struct platform_driver::remove()` returns `void`, not `int`, as of
  Linux 6.11.** Two drivers in this tree register a `platform_driver`:
  `marlin_driver` (`BSP/platform/wcn_boot.c`, `marlin_remove()`) and
  `sprdwl_driver` (`WIFI/wl_core.c`, `sprdwl_remove()`). Both functions
  only ever returned `0`, so both are now version-guarded
  (`LINUX_VERSION_CODE < 6.11.0` keeps `int`/`return 0`, else `void`
  with no return statement). I also checked for any other
  `platform_driver`/`i2c_driver`/`usb_driver`/`spi_driver` registration
  in the buildable set — there are none; `BSP/sdio/sdiohal_main.c`'s
  `struct sdio_driver` was already correctly `void`-returning (SDIO bus
  driver `remove()` was never `int`-returning, so no change was needed
  there).

- **Module load ordering**: `sprdwl_ng.ko` calls symbols
  `uwe5621_bsp_sdio.ko` exports (`sprdwcn_bus_*`, `bus_chn_init`,
  `module_ops_register`, ...). `BUILD.bazel` already declared
  `deps = [":uwe5621_bsp_sdio"]` on the `sprdwl_ng` `ddk_module`, which
  is what makes kleaf propagate `uwe5621_bsp_sdio`'s `Module.symvers`
  into `sprdwl_ng`'s build — that's both how the undefined-symbol link
  succeeds *and* how `depmod`/`modprobe` learn the correct load order.
  As a belt-and-suspenders addition (covers `insmod`-based or other
  loading paths that don't consult `depmod`'s dependency graph), I also
  added `MODULE_SOFTDEP("pre: uwe5621_bsp_sdio");` next to
  `sprdwl_ng`'s other `MODULE_*()` declarations in `WIFI/wl_core.c`.

- I re-audited the full buildable set once more for a handful of other
  commonly-broken-by-5.15+ patterns (`do_gettimeofday()`,
  `dma_zalloc_coherent()`, legacy 3-arg `access_ok()`, raw
  `struct file_operations` used where `struct proc_ops` would be
  required) — no further hits. The remaining `struct file_operations`
  usages (`wcn_op.c`, `wcn_log.c`, `sdiohal_ctl.c`, `wl_core.c`) are all
  `misc_register()`/`cdev_add()`/`debugfs_create_file()` based, which
  correctly still use `file_operations` (only actual `/proc` entries
  registered via `proc_create()` need `proc_ops`, and the one file that
  does that — `wcn_procfs.c` — was already fixed in the first round).

## Third build-log round (real 6.12 kleaf modpost)

- **`vfs_getattr` from a restricted namespace.** My first-round fix for
  `set_fs()`/`vfs_stat()` (see above) used `kern_path()` +
  `vfs_getattr()`. That was wrong: `vfs_getattr()` lives in the
  `VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver` symbol
  namespace and is intentionally off-limits to driver modules —
  modpost correctly rejected it. Both call sites only ever read
  `stat->size`, so `wcn_vfs_stat()` in `wcn_kcompat.h` now just does a
  plain `filp_open()` + `i_size_read(file_inode(filp))` + `filp_close()`
  instead — no restricted symbols, no address-space override, and it
  fits in `struct kstat` unchanged so `rdc_debug.c`'s two call sites
  didn't need to change at all.

- **`local symbol 'X' was exported`** for `mdbg_assert_read`,
  `mdbg_loopcheck_read`, `mdbg_at_cmd_read` in
  `BSP/platform/wcn_procfs.c`. This is a pre-existing bug in the vendor
  driver, not a kernel-version issue — each of these three functions is
  declared `static` (internal linkage) but was also wrapped in
  `EXPORT_SYMBOL_GPL()`, which is a contradiction newer `modpost` now
  correctly rejects. All three are only ever referenced within the same
  file (as `.pop_link` entries in `mdbg_proc_ops[]`), so the exports
  were always dead code; I removed the three `EXPORT_SYMBOL_GPL()`
  lines rather than making the functions non-static, since nothing
  outside this module could ever legitimately have linked against a
  `static` function anyway. I also scanned the full buildable set
  programmatically for the same `static` + `EXPORT_SYMBOL(_GPL)`
  contradiction — no other instances.

- **Remaining `WARNING: ... undefined!` entries** (`filp_open`,
  `extern_wifi_set_enable`, `extern_bt_set_enable`,
  `wifi_irq_trigger_level`, `wifi_irq_num`, `call_usermodehelper`,
  `mmc_power_up`) did **not** fail this build — only the two `ERROR:`
  lines above did. I didn't touch any of them:
  - `extern_wifi_set_enable`, `extern_bt_set_enable`,
    `wifi_irq_trigger_level`, `wifi_irq_num` are declared `extern`
    inside `#ifdef CONFIG_AML_BOARD` in `wcn_boot.c`/`sdiohal_main.c`
    — they're meant to be supplied by Amlogic's own board/platform
    glue code elsewhere in your kernel tree (GPIO/power-control
    shims for this board), not by this driver. If they're still
    unresolved at `insmod` time, the fix is on the board-glue side
    (a missing `deps` entry on whatever target provides them, or a
    module load-order issue), not in this driver's source.
  - `filp_open`, `call_usermodehelper`, `mmc_power_up` are ordinary
    kernel-exported symbols (`fs/open.c`, `kernel/umh.c`,
    `drivers/mmc/core/core.c`) that should resolve once linked against
    the real `vmlinux`/full `Module.symvers`; this can be an artifact
    of building a single `ddk_module` target in isolation. Worth
    re-checking after a full `common_drivers` build, but not something
    to chase from this driver's source.

## Fourth build-log round (real 6.12 kleaf build, WIFI module)

With the BSP module now building clean, this round surfaced the WIFI
module's own break set -- almost entirely the fallout of cfg80211's
MLO (multi-link operation, i.e. Wi-Fi 7) rework, which landed across
several kernel releases and touches a lot of `struct cfg80211_ops`
signatures. This driver has no MLO support, so every fix below just
threads an unused `link_id` parameter through or adjusts a struct
layout -- no behavioral changes.

- **`WLAN_AKM_SUITE_OWE` macro redefined.** `linux/ieee80211.h` grew
  its own definition of this AKM suite at some point after this
  driver's own copy (`WIFI/cfg80211.h`) was written. Wrapped the
  driver's definition in `#ifndef`. This single fix unblocked
  compilation of most other WIFI/*.c files, which had been failing on
  this before reaching any of their own code.

- **`dev_addr` read discarding `const`** in `sprdwl_cfg80211_open()`
  (`cfg80211.c`): the local `mac` pointer and `sprdwl_open_fw()`'s
  `mac_addr` parameter were only ever read from, never written
  through, so both were changed to `const u8 *`.

- **`len` set-but-unused** in `sprdwl_event_ftm()` (`rtt.c`): the
  `len -= sizeof(sub_event);` decrement had no effect on anything
  downstream (the parameter isn't read again) -- removed.

- **`random_ether_addr()` undeclared** (`main.c`): this very old
  function was removed at some point; replaced with `eth_random_addr()`
  (its modern equivalent, available unconditionally since 3.9).

- **`struct cfg80211_roam_info.bss` doesn't exist** (`cfg80211.c`):
  MLO restructured this struct so per-link fields (`bss`, `bssid`,
  `channel`, `addr`) live in a `links[]` array instead of being
  top-level. Since this driver never sets `.valid_links`, it's always
  a legacy single-link roam, so the fix is simply
  `.links[0].bss = bss` instead of `.bss = bss`, version-guarded at
  Linux 6.1 (see below for why 6.1).

- **`genl_ops` vs `genl_split_ops` mismatch** for `.pre_doit`/
  `.post_doit` (`npi.c`): genetlink's "split ops" rework changed the
  type these callbacks receive. Neither callback here actually
  dereferences the `ops` argument, so this is a pure type fix,
  version-guarded. **This is the one threshold in this round I'm
  least sure of** (currently `KERNEL_VERSION(6, 3, 0)`, a best
  estimate) -- flagging this specifically in case a 6.2 build reports
  a mismatch here; the fix would just be moving this one guard up or
  down.

- **`cfg80211_ops` callback signature changes** (`cfg80211.c`,
  `cmdevt.c`), all part of the MLO rework, but landing at two
  *different* points in kernel history that I verified independently
  against actual upstream commits rather than assuming a single
  cutover:
  - **Linux 6.1** (upstream commit `7b0a0e3c3a88`, "wifi: cfg80211: do
    some rework towards MLO link APIs" -- confirmed via the commit
    that also modified the ath6kl driver's equivalent callbacks):
    - `.add_key`, `.del_key`, `.set_default_key` each gained an
      `int link_id` parameter (inserted right after `ndev`).
    - `.stop_ap` gained an `unsigned int link_id` parameter.
    - `cfg80211_ch_switch_notify()` gained a third
      `unsigned int link_id` argument (fixed in `cmdevt.c`).
  - **Linux 6.7** (upstream commit `bb554417c453`, "wifi: cfg80211:
    split struct cfg80211_ap_settings" -- confirmed via the commit
    that introduced `struct cfg80211_ap_update`, a distinct/later
    change from the 6.1 wave above):
    - `.change_beacon` now takes `struct cfg80211_ap_update *`
      instead of `struct cfg80211_beacon_data *`; the driver now
      unwraps `&update->beacon` to keep the existing body unchanged.
  - `.tdls_mgmt` gained an `int link_id` parameter (inserted right
    after `peer`). I could not find as clear a commit reference for
    this one specifically, so it's guarded at the same 6.7 threshold
    as `.change_beacon` by analogy (both are later/AP-adjacent
    changes) -- **this is the other threshold worth double-checking**
    if a 6.2 build complains about `tdls_mgmt`.

  I want to flag explicitly: I initially guessed `.stop_ap`'s
  `link_id` was part of the *later* 6.7 wave (by analogy with
  `.change_beacon`, since both are AP-related), then caught the
  mistake by rechecking the actual patch content and found it's
  actually part of the *earlier* 6.1 commit alongside
  `cfg80211_ch_switch_notify()`. I mention this not to bury it in a
  diff, but because it's a good illustration of why the 6.2 build in
  particular is the one to watch here: these two waves (6.1 and 6.7)
  straddle it, so getting a threshold wrong in either direction will
  surface as a concrete, easy-to-fix compile error on that specific
  target and nowhere else.

## Fifth build-log round (real 6.12 kleaf build, WIFI module)

- **`__write_overflow_field` / FORTIFY_SOURCE errors** in `wl_intf.c`
  and `cmdevt.c`. The actual call sites weren't named in the log (the
  diagnostic only pointed at the `fortify-string.h` internals that
  every fortified `memcpy()` expands through), so this took a source
  audit rather than a direct line-by-line fix.

  Root cause: this driver declares its variable-length trailing
  struct fields the old GNU way --
  `u8 data[0];` / `struct foo bar[0];` (a "zero-length array") --
  instead of the C99 flexible-array-member syntax, `u8 data[];`.
  Both spellings behave identically for `sizeof()` and memory layout,
  but modern FORTIFY_SOURCE's stricter bounds checking
  (`__builtin_dynamic_object_size`) doesn't reliably recognize a
  `[0]`-sized field as "intentionally unbounded" the way it does a
  true `[]` flexible-array member, so it can treat the field as
  *actually* zero bytes and flag any `memcpy()`/`memset()` into it as
  an overflow -- even though the field was always meant to be sized
  by the surrounding allocation (`sprdwl_alloc_work(len)` and
  similar).

  Fixed by converting every trailing zero-length array field in the
  buildable source set to proper `[]` flexible-array-member syntax:
  `WIFI/cfg80211.h`, `cmdevt.h`, `cmdevt.c`, `msg.h`, `nan.h`,
  `sprdwl.h`, `work.h`, `vendor.h`, `rx_msg.h`, `reorder.h`, `rtt.h`,
  `rtt.c`, and (for consistency, though it hadn't actually triggered
  an error yet) `BSP/platform/wcn_dump.c`. Verified each one is the
  last member of its struct (a hard C99 requirement for `[]`) before
  converting -- one of them (`cmdevt.h`'s `buf[0]`) is the last member
  of a union that is itself the last member of its enclosing struct,
  which is also valid.

  I did an exhaustive regex sweep of the whole buildable set (BSP +
  WIFI, both headers and .c files) for this pattern afterward and
  found no remaining instances, including a broadened pattern that
  wasn't type-restricted (my first pass only matched primitive types
  like `u8`/`u16`/`char`, which is why the `struct foo bar[0]` cases
  in `vendor.h`/`rx_msg.h`/`reorder.h`/`rtt.h`/`rtt.c` needed a
  second pass).

## Sixth round: real build against a third target (CoreELEC's Amlogic 5.15 kernel)

Up to this point every build log had come from the Android/AOSP
`aml0131` `common16-6.12` tree via Bazel/kleaf. This round's log came
from a genuinely different target: **CoreELEC** (a community,
Kodi-focused Linux distribution for Amlogic boxes), building this
tree's *original, untouched* `BSP/Makefile` via plain kbuild
(`make modules`), against its own Amlogic 5.15 kernel. Worth noting
explicitly: since I only ever added Bazel files *alongside* the
original per-directory `Makefile`s (never modified them), the same
`.c`/`.h` source fixes made throughout this port benefit both build
paths automatically -- this round is proof that held up in practice.

- **`filldir_t` return type: a genuine cross-tree ABI divergence, not
  just a version-threshold question.** Round three's fix (converting
  `find_callback()` in `wcn_parn_parser.c` to return `bool`, based on
  mainline's conversion landing at Linux 5.1) is correct for the
  Android 6.12 tree -- confirmed, since that BSP module has built
  clean there across every round since. But CoreELEC's Amlogic 5.15
  kernel rejected that same `bool`-returning function with the exact
  inverse error (expects `int`), despite reporting a *newer*
  `LINUX_VERSION_CODE` (5.15) than the mainline commit that made this
  change (5.1, merged 2019). That means CoreELEC's tree, despite its
  version label, has not picked up (or has reverted) this specific
  upstream VFS commit -- a real inconsistency between two trees that
  both call themselves "Amlogic 5.15-class," not something a single
  `LINUX_VERSION_CODE` check can distinguish between.

  Since there's no reliable compile-time signal available to
  auto-detect which convention a given tree actually uses (this is
  exactly the class of problem out-of-tree modules like ZFS or Nvidia's
  driver solve with an autoconf-style build-time probe, which felt
  like more infrastructure than this simple Makefile setup warrants),
  I added an explicit escape-hatch macro instead:
  `WCN_FILLDIR_RETURNS_INT`. `wcn_parn_parser.c` now has three
  branches: forced-`int` (if that macro is defined), version-gated
  `bool` (`LINUX_VERSION_CODE >= 5.1.0`, the mainline-correct default
  -- this is what the already-working Android 6.12 build uses), and
  the historical pre-5.1 `int` fallback. `BSP/Makefile` has a
  commented-out `ccflags-y += -DWCN_FILLDIR_RETURNS_INT` right near
  the top with an explanation of exactly which build error it fixes
  -- **uncomment that line for the CoreELEC build specifically**; leave
  it commented out for the Android/Bazel 6.12 target, which needs the
  default `bool` behavior it already has.

  I want to flag this one clearly: unlike every other version-guarded
  fix in this port, this isn't a "some kernel version changed an API"
  situation with one right answer per `LINUX_VERSION_CODE` -- it's
  evidence that at least one of the vendor trees you're targeting
  doesn't track upstream cleanly on this specific ABI, and version
  numbers alone can't tell the two apart. If other CoreELEC build
  errors turn out to have the same shape (a "5.15" tree behaving like
  an older kernel on some other specific API), the same
  escape-hatch-macro pattern is the right tool to reach for again
  rather than trying to adjust a shared version threshold.

## Seventh round: CoreELEC-specific symbol namespace requirement

The BSP module now compiles clean on CoreELEC (all the `filldir_t`
work from the previous round held up) and gets all the way to
`MODPOST`, where it fails with:

```
ERROR: modpost: module uwe5621_bsp_sdio uses symbol kernel_write from
       namespace VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver,
       but does not import it.
ERROR: modpost: module uwe5621_bsp_sdio uses symbol kernel_read ...
ERROR: modpost: module uwe5621_bsp_sdio uses symbol filp_open ...
```

This is also the answer to the standalone `filp_open` question from
earlier in this conversation: on CoreELEC's Amlogic 5.15 kernel,
`filp_open()`/`kernel_read()`/`kernel_write()` are genuinely gated
behind that symbol namespace (kernel's "Symbol Namespaces" feature --
`EXPORT_SYMBOL_NS()` / `MODULE_IMPORT_NS()`), and a module that calls
them without declaring the import fails at `MODPOST` (a hard error on
this kernel's config; the upstream kernel docs describe the default
behavior as a `modpost` warning plus a runtime `insmod` rejection,
so CoreELEC's build is evidently configured to treat it as an
immediate build failure). On the Android common16-6.12 tree we'd been
building against via Bazel up to this point, `filp_open` only ever
showed up as a soft `WARNING: ... undefined!` from `modpost` -- not
this "uses symbol from namespace" error -- implying these specific
symbols aren't namespaced the same way on that tree.

Fixed by adding `MODULE_IMPORT_NS(VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver);`
next to the existing `MODULE_LICENSE()`/`MODULE_AUTHOR()` block in
`BSP/platform/wcn_boot.c` (for `uwe5621_bsp_sdio`, which uses these
symbols in `rdc_debug.c` and elsewhere), and the equivalent in
`WIFI/wl_core.c` (for `sprdwl_ng`, which independently uses the same
three symbols in `dbg_ini_util.c`, `main.c`, `npi.c`, `rf_marlin3.c`,
and `rx_msg.c` -- added proactively since the WIFI module hasn't been
built on CoreELEC yet in any log I've seen, but given the BSP module
just hit this, the WIFI module very likely will too once you get that
far).

This macro takes an unquoted/bareword namespace identifier in every
kernel version we target (5.15/6.2/6.12) -- the syntax changed to
require a quoted string literal, but not until Linux 6.13, which is
past our ceiling, so no version guard is needed. It's also safe to
declare unconditionally on kernels where these symbols *aren't*
namespaced (including the Android 6.12 tree): importing a namespace
that doesn't exist on a given kernel is simply a no-op there, so this
shouldn't be able to regress the already-working Bazel/6.12 build.

I checked `tty-sdio` for the same three symbols -- it doesn't call
any of them, so no equivalent fix was needed there.

## Eighth round: WIFI module's BSP include path was broken on CoreELEC

`uwe5621_bsp_sdio.ko` now builds *and links* successfully on CoreELEC
(round seven's `MODULE_IMPORT_NS()` fix held). The WIFI module
(`sprdwl_ng`) then failed immediately with:

```
fatal error: 'wcn_kcompat.h' file not found
fatal error: 'wcn_bus.h' file not found
```

This is a real, **pre-existing bug in the original vendor Makefile**,
unrelated to anything I've changed source-wise -- it just never
surfaced until a build system passed `$(M)` as an absolute path.
`WIFI/Makefile` located the BSP module's `include/` directory (needed
for `wcn_bus.h`, `marlin_platform.h`, and now also `wcn_kcompat.h`)
via:

```
ccflags-y += -I$(KERNEL_SRC)/$(M)/../BSP/include/
```

This only produces a valid path when `$(M)` happens to already be
*relative to* `$(KERNEL_SRC)` -- prepending `$(KERNEL_SRC)/` onto an
already-absolute `$(M)` (as CoreELEC's build does: both BSP's and
WIFI's `$(M)` are absolute paths under `/build/build.CoreELEC-.../`)
produces a nonsense concatenated path that silently doesn't exist, so
none of `-I`'s target directory's headers are found.

`BSP/Makefile` already had the fix for this same class of problem,
just applied inconsistently: alongside the same broken
`$(KERNEL_SRC)/$(M)/...` pattern (harmlessly redundant there, since
it's dead weight -- extra `-I` flags pointing at nonexistent
directories are silently ignored by the compiler as long as *some*
other `-I` flag finds the actual headers), it also has working
`-I$(src)/include/`-style flags. `$(src)` is kbuild's standard
"directory containing the current Makefile" variable, and it resolves
correctly regardless of whether the invoking build system passes
`$(M)`/`$(KERNEL_SRC)` as absolute or relative paths -- unlike
`$(KERNEL_SRC)/$(M)/...`, which only works by coincidence for
whichever specific invocation style the original vendor happened to
test against.

Fixed by changing `WIFI/Makefile`'s BSP-include line to
`-I$(src)/../BSP/include/`, mirroring the pattern `BSP/Makefile`
already uses correctly for its own internal include paths. I left the
three harmless-but-still-technically-broken
`-I$(KERNEL_SRC)/$(M)/...` lines already in `BSP/Makefile` alone
(lines pointing at `include/`, `platform/`, `platform/rf/`) --
they're inert there since the working `$(src)`-based equivalents
already cover everything needed, and touching working code for
stylistic consistency alone isn't worth the extra diff/risk. Flagging
them here in case you want to clean them up anyway for future-proofing.

This is purely a kbuild-path fix and doesn't touch the Bazel build at
all: `BUILD.bazel`'s `sprdwl_ng` target already references
`:uwe5621_bsp_headers` directly as a Bazel target dependency rather
than through this Makefile's `ccflags-y`, so it was never affected by
this bug in the first place.

## Ninth round: flexible array member inside a union

WIFI module compilation now gets past the include-path fix and fails
on:

```
error: flexible array member 'buf' in a union is not allowed
                u8 buf[];
```

This is fallout from round 5's FORTIFY_SOURCE sweep (converting
zero-length arrays `field[0]` to proper C99 flexible-array-member
syntax `field[]`), for exactly the one case I'd flagged at the time as
worth double-checking: `struct sprdwl_cmd_11v` in `cmdevt.h` has a
`union { u32 value; u8 buf[0]; };`, and while a flexible array member
as the last field of a plain `struct` is universally fine, a flexible
array member *inside a `union`* is much more strictly disallowed --
this specific compiler (CoreELEC's Amlogic 5.15 toolchain) rejects it
outright as a hard error, where GCC's older zero-length-array
extension (`[0]`) was tolerated in that same position.

Reverted just this one field back to `u8 buf[0]`. I checked whether
that reintroduces the original FORTIFY risk it was converted to avoid
in round 5, and it doesn't: `buf` turns out to be entirely unused
throughout this driver -- only `.value` (the other union member) is
ever read or written, at both of `sprdwl_cmd_11v`'s two call sites in
`cmdevt.c` -- so `buf` was never actually a `memcpy()`/`__write_overflow_field`
target in the first place. Reverting it is a pure compatibility fix
with no trade-off.

I also re-swept the whole set of fields converted in round 5 for any
other flexible-array-member-inside-a-union occurrences, since this
compiler's strictness here means any other instance would hit the
identical error. Found none -- this was the only one.

## Tenth round: the filldir_t fix needed to be the default, not opt-in

The exact same `filldir_t` error from round six came back on a fresh
build. Root cause: my round-six fix required a manual step (uncomment
`ccflags-y += -DWCN_FILLDIR_RETURNS_INT` in `BSP/Makefile`) that
apparently didn't make it into this build. Rather than rely on that
being remembered/reapplied on every fresh checkout, I flipped the
default: `BSP/Makefile` now enables `-DWCN_FILLDIR_RETURNS_INT`
unconditionally, with the "comment this back out if you don't need
it" instruction moved into the comment instead of being the required
action.

This is safe to default on because the two build paths this driver
supports are fully separate: the Android/AOSP target builds
exclusively through `BUILD.bazel`'s `ddk_module` (which sets its own
`local_defines` and never reads `BSP/Makefile`'s `ccflags-y` at all),
while `BSP/Makefile` -- the traditional kbuild path -- is, as far as
every build log so far shows, only ever used for CoreELEC-style
builds. I double-checked `BUILD.bazel` doesn't reference
`WCN_FILLDIR_RETURNS_INT` anywhere, so the already-working Android
6.12 Bazel build keeps using the correct `bool`-returning default it
always has, unaffected by this change.

## Eleventh round: CoreELEC has *newer* cfg80211 MLO APIs than its version implies

WIFI module compilation reached much further this round (past the
`wcn_kcompat.h`/Makefile fixes) and produced five real errors, all in
the cfg80211 MLO surface -- but this time in the *opposite* direction
from the `filldir_t` situation: CoreELEC's "5.15" kernel already has
the Linux 6.1 cfg80211 MLO (multi-link operation) rework -- despite a
version number that predates the actual 6.1 merge of that work by a
wide margin. Concretely:

- `struct cfg80211_roam_info` has no `.bss` field -- it wants
  `.links[0].bss` (the round-4 fix for the Android 6.12 tree, but my
  `LINUX_VERSION_CODE >= 6.1.0` guard doesn't fire on a kernel
  reporting 5.15, so it was using the old, wrong branch here).
- `.add_key`, `.del_key`, `.set_default_key`, `.stop_ap` all want the
  `link_id`-carrying signatures, same story.
- `cfg80211_ch_switch_notify()` wants **4** arguments, not the 2 the
  code was passing (nor even the 3 that the round-4 fix already
  correctly handles for Android 6.12) -- this one isn't just "CoreELEC
  is ahead of its version label" in the same way as the others, since
  I confirmed via the working Android 6.12 build logs that mainline's
  own signature at 6.12 only needs 3 arguments. CoreELEC's 4th
  argument is a genuine vendor addition beyond even current mainline.
  I found a real precedent for this exact situation: another MLO-era
  vendor driver (`aic8800`) hit an identical "expected 4" error and
  resolved it by passing `(dev, chandef, 0, 0)` -- strongly suggesting
  a puncturing-bitmap parameter (mainline's sibling function,
  `cfg80211_ch_switch_started_notify`, already has one; it's plausible
  some vendor trees added the same to the plain notify function ahead
  of/independent from mainline). Since the extra argument is a literal
  `0` either way, getting its exact type slightly wrong carries very
  low risk -- integer literals convert cleanly regardless of the
  parameter's real width/signedness; only the *count* (4) actually
  had to be right, and that's directly confirmed by the error text.

Given this is the same class of problem as the `filldir_t` divergence
-- a real API mismatch that `LINUX_VERSION_CODE` can't resolve because
this vendor tree doesn't track upstream consistently -- I used the
same escape-hatch pattern:

- `WCN_CFG80211_HAS_MLO_LINK_ID` (defined by default in
  `WIFI/Makefile`, same "kbuild-only, never read by Bazel" reasoning
  as `WCN_FILLDIR_RETURNS_INT`) now governs the `.bss`/`links[0].bss`,
  `.add_key`/`.del_key`/`.set_default_key`, and `.stop_ap` branches in
  `cfg80211.c` -- replacing the `LINUX_VERSION_CODE >= 6.1.0` checks
  there with `defined(WCN_HAVE_CFG80211_MLO_LINK_ID)` (an internal
  macro in `wcn_kcompat.h` that's set either by the override or by the
  version check, so non-CoreELEC/Bazel builds keep exactly the
  behavior they had before this round).
- `WCN_CFG80211_CH_SWITCH_NOTIFY_HAS_PUNCT_BITMAP` (also defaulted on
  in `WIFI/Makefile`) adds a third tier to the existing
  `cfg80211_ch_switch_notify()` call in `cmdevt.c`: 4-arg (CoreELEC,
  forced) / 3-arg (mainline 6.1+, confirmed correct for Android 6.12)
  / 2-arg (pre-6.1) -- rather than replacing the existing, proven-correct
  3-arg tier.

I did *not* touch the `.change_beacon`/`.tdls_mgmt` (Linux 6.7 wave)
guards -- the CoreELEC build didn't report any error on those, which
is itself useful evidence: this vendor tree has backported the 6.1 MLO
wave but apparently not the later 6.7 one, so those two stay exactly
as they were (still gated on `LINUX_VERSION_CODE >= 6.7.0`, no
override).

## Twelfth round: WIFI module compiles and links, but modpost can't see BSP's exports

`sprdwl_ng.o` now compiles and links successfully (every `.c` file in
the module, all the way through `LD [M] .../WIFI/sprdwl_ng.o`) --
round eleven's cfg80211 MLO fixes held. It then failed at `MODPOST`
with ten (plus two more, suppressed as "too many") `undefined!`
errors, all for symbols `uwe5621_bsp_sdio` exports and `sprdwl_ng`
calls into: `marlin_get_wcn_chipid`, `marlin_get_ant_num`,
`cali_ini_need_download`, `stop_marlin`/`start_marlin`,
`marlin_reset_callback_register`/`_unregister`, `wcn_get_chip_name`,
`mdbg_assert_interface`, `get_wcn_bus_ops`, and others.

This is a standard kbuild multi-module gap, not a source or API
problem: the top-level `Makefile` builds `BSP` before `WIFI` (so
`BSP/Module.symvers` already exists by the time `WIFI` compiles), but
nothing ever told *WIFI's* `modpost` invocation to also check that
file when resolving undefined symbols -- each out-of-tree module
build's `modpost` only looks at its own `Module.symvers` (plus
whatever the running kernel already provides) unless told otherwise.
`KBUILD_EXTRA_SYMBOLS` is exactly the mechanism kbuild provides for
this (documented in `Documentation/kbuild/modules.rst`: a second
out-of-tree module that needs to resolve against a sibling module's
exported symbols).

Added `KBUILD_EXTRA_SYMBOLS += $(src)/../BSP/Module.symvers` to
`WIFI/Makefile`, using `$(src)` for the same absolute-path-safety
reason as the include-path fix from round eight. I verified all ten
named symbols are genuinely `EXPORT_SYMBOL`'d somewhere in
`uwe5621_bsp_sdio`'s buildable source set (mostly `wcn_boot.c`, plus
one each in `wcn_procfs.c` and `wcn_bus.c`), so this should resolve
the two suppressed ones as well.

This is purely a kbuild-Makefile fix and doesn't touch the Bazel
build: `BUILD.bazel`'s `sprdwl_ng` target already has
`deps = [":uwe5621_bsp_sdio"]`, which is kleaf's equivalent mechanism
for propagating a sibling `ddk_module`'s `Module.symvers` -- that's
been correct since the very first round of this port.

## Recommended next step

Build each `ddk_module` against your actual 5.15, 6.2, and 6.12 trees and
address any remaining `-Werror`/type-mismatch fallout; the fixes above
should cover the systemic breaks, but a real compile pass is the only way
to be certain for a driver this size.
