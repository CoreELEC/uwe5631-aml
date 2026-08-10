# tty-sdio (sprdbt_tty): port to 5.15 / 6.2 / 6.12 + Bazel (DDK) build

This is the BT half of the Unisoc UWE5621DS WiFi+BT combo chip: a
tty-line-discipline-style HCI transport that exposes a `/dev/ttyBT0`
style character device to userspace, carrying frames over the SDIO
bus channel exported by the `uwe5621_bsp_sdio` module (the same one
built by the `uwe5621ds` driver tree). It does not register its own
`sdio_driver` or an in-kernel `hci_dev` -- it calls `sprdwcn_bus_*`
directly, so it depends on `uwe5621_bsp_sdio`'s exported symbols the
same way `sprdwl_ng` did.

## What changed

### Build system
- Added `BUILD.bazel` defining one `ddk_module`, `sprdbt_tty`, plus a
  `ddk_headers` target for this driver's own `include/`.
- `deps = ["//driver_modules/wifi_bt/wifi/unisoc/uwe5621:uwe5621_bsp_sdio"]`
  and `hdrs` pulling in that module's `uwe5621_bsp_headers` -- this
  driver needs `wcn_bus.h` and `marlin_platform.h` from there, exactly
  like `sprdwl_ng` did.
- **You will need to adjust the package path** in that label
  (`//driver_modules/wifi_bt/wifi/unisoc/uwe5621:...`) to match where
  you actually place this driver relative to the `uwe5621ds` tree --
  I've assumed a sibling layout like
  `driver_modules/wifi_bt/bt/unisoc/tty-sdio/`, matching the
  `wifi_bt/<wifi|bt>/unisoc/<chip>` shape visible in your build logs,
  but I don't know your exact directory layout for this driver.
- Added `ddk_kconfig.sprdbt_tty` and a fuller documentation `Kconfig`,
  same two-tier pattern as the other driver.
- The original `Makefile` is left in place, untouched, for reference;
  it isn't used by the Bazel build.
- `alignment/sitm.c` and `alignment/sitm.h` are **not** part of the
  build -- they're an unused leftover copy (the original Makefile's
  `sprdbt_tty-objs` list only references the root `sitm.c`, and
  nothing else in the tree includes anything from `alignment/`).
  Left in the tree for reference but excluded from `BUILD.bazel`.

### Source changes for kernel 5.15 / 6.2 / 6.12

This is a much smaller codebase (~2,400 lines) than `uwe5621ds`, and
had far fewer breaks -- most of it was already portable. Everything
found and fixed:

1. **`alloc_tty_driver()` removed (Linux 5.14).** `mtty_tty_driver_init()`
   in `tty.c` now calls `tty_alloc_driver(MTTY_DEV_MAX_NR, TTY_DRIVER_REAL_RAW)`
   instead -- which also folds in the `driver->flags = TTY_DRIVER_REAL_RAW`
   line that used to be set separately -- and checks the result with
   `IS_ERR()`/`PTR_ERR()` instead of a NULL check, since the new
   allocator returns an error pointer on failure rather than NULL.
   No version guard needed: this landed well before our 5.15 floor.

2. **`put_tty_driver()` removed (Linux 5.15, i.e. exactly at our
   floor).** Both call sites in `tty.c` (the `tty_register_driver()`
   failure path and `mtty_tty_driver_exit()`) now call
   `tty_driver_kref_put()` instead. No version guard needed for the
   same reason as above.

3. **`PDE_DATA()` renamed to `pde_data()` (Linux 5.17).** One call
   site in `lpm.c` (`bluesleep_open_proc_btwrite()`), fixed with a
   version guard (this file already had `linux/version.h` and used
   `LINUX_VERSION_CODE` guards elsewhere, so no new infrastructure was
   needed).

4. **`proc_create()` needs `struct proc_ops`, not `struct
   file_operations` (Linux 5.6).** This one wasn't guarded at all in
   the original source. `lpm_proc_btwrite_fops` in `lpm.c` is now
   defined as a `struct proc_ops` for 5.6+ (version-guarded, with the
   old `file_operations` form kept for completeness even though it's
   dead code at our floor). Field mapping is a pure rename
   (`.open`->`.proc_open`, `.read`->`.proc_read`,
   `.write`->`.proc_write`, `.release`->`.proc_release`); `proc_ops`
   has no `.owner` field, so that line was dropped. The callback
   function signatures didn't need to change.

5. **`struct platform_driver::remove()` returns `void` as of Linux
   6.11.** `mtty_remove()` in `tty.c`, same fix pattern as the two
   `platform_driver`s in the `uwe5621ds` tree (it only ever returned
   `0`, so it's a pure signature change, version-guarded at 6.11).

### Things I checked and found already fine, or not applicable
- No `set_fs()`/`get_fs()`/`vfs_read()`/`vfs_write()`/`vfs_stat()`
  usage anywhere in this driver.
- No `dev->dev_addr` writes, `class_create()`, `kzfree()`,
  `.ndo_do_ioctl`, or zero-length-array (`field[0]`) struct members
  -- I ran the same sweeps used on `uwe5621ds` and this tree is clean
  on all of them.
- No `cfg80211`/MLO surface at all (this is a tty/HCI-transport
  driver, not a wifi dridriver), so none of the `uwe5621ds` WIFI
  module's fixes apply here.
- `lpm.c` already correctly version-guards its `<linux/wakelock.h>`
  vs. local `include/wakelock.h` choice (`#if LINUX_VERSION_CODE >=
  KERNEL_VERSION(4, 9, 0)` picks the local shim, which is always true
  at our 5.15+ floor) -- no change needed there.
- `WIFI/wl_intf.h` in the `uwe5621ds` tree has an *unguarded*
  `#include <linux/wakelock.h>`, but it's behind `#ifdef
  SPRDWL_TX_SELF`, which isn't in that module's `local_defines`, so
  it's never actually compiled and I didn't touch it. Flagging this
  only because I initially (incorrectly) read it as evidence that
  this specific Android 6.12 tree ships a legacy `linux/wakelock.h`
  -- it isn't evidence of that at all, since that branch has never
  actually been compiled in any of our build rounds. If you ever
  enable `SPRDWL_TX_SELF`, treat that include as unverified.

## Second build-log round (real 6.12 kleaf build)

- **`struct tty_operations::write`/`.write_room` signature change**
  (Linux 6.6.1, part of a wider tty-core `unsigned char`/`int` ->
  `u8`/`size_t`/`ssize_t`/`unsigned int` modernization). `mtty_write_plus()`
  and `mtty_write_room()` in `tty.c` are now version-guarded between
  the old and new signatures; the exact 6.6.1 threshold is taken from
  a real reference driver (`tty0tty`) that already carries this same
  guard, rather than guessed.

- **`of_property_read_string()` undeclared / `struct of_device_id`
  incomplete type.** Both trace back to the same root cause: this
  file's `#include <linux/of_device.h>` was wrapped in `#ifdef
  CONFIG_OF`, and `of_property_read_string()` itself lives in
  `<linux/of.h>`, which wasn't included at all. At our 5.15+ floor
  both headers exist unconditionally (they provide harmless
  static-inline stubs when `CONFIG_OF=n`), so the fix was to make
  both includes unconditional rather than re-adding a `CONFIG_OF`
  guard around them -- this also implies `CONFIG_OF` isn't defined
  for this specific DDK module compilation, which is worth knowing
  independent of this fix.

- **`-Werror,-Wformat`: `%d` used for a `size_t` argument.** One
  genuine case in `tty.c` (`woble_set_store()`'s `pr_info(...,
  count, ...)`, where `count` is the sysfs `store` callback's
  standard `size_t count` parameter) -- fixed with `%zu`. I checked
  every other `%d` near a variable named `count`/`len` in the tree by
  hand; all the others are against genuinely `int`-typed locals
  (different functions, coincidentally similar variable names), so
  they were left alone.

## Third build-log round (real CoreELEC 5.15 kbuild build)

- **`.write_room` return-type mismatch** (`unsigned int (*)(struct
  tty_struct *)` expected, `int (struct tty_struct *)` supplied).
  This is the same pattern seen repeatedly on the `uwe5621ds` sibling
  driver: CoreELEC's Amlogic 5.15 kernel has backported part of a
  later mainline API change (here, the Linux 6.6.1 tty-core
  `unsigned char`/`int` -> `u8`/`size_t`/`ssize_t`/`unsigned int`
  cleanup) without a matching version bump. What makes this one
  notable: only `.write_room` errored -- `.write`, guarded by the
  exact same `LINUX_VERSION_CODE >= 6.6.1` check right next to it,
  compiled fine with its old `int`-returning form. So this vendor
  tree has backported *half* of a change that normally lands as one
  commit, and the two callbacks needed independent guards rather than
  sharing one.

  Added `WCN_TTY_WRITE_ROOM_RETURNS_UINT`, the same escape-hatch
  pattern as `uwe5621ds`'s `WCN_FILLDIR_RETURNS_INT` /
  `WCN_CFG80211_HAS_MLO_LINK_ID`: `mtty_write_room()`'s guard now
  checks `defined(WCN_TTY_WRITE_ROOM_RETURNS_UINT) ||
  LINUX_VERSION_CODE >= KERNEL_VERSION(6, 6, 1)`, and the `Makefile`
  defines it by default for the same reason those other overrides
  are defaulted on in the `uwe5621ds` tree: this `Makefile` (the
  traditional kbuild path) is only ever exercised by CoreELEC-style
  builds, never by the Android/Bazel target, which builds exclusively
  through `BUILD.bazel` and never reads this file's `ccflags-y` at
  all -- confirmed `BUILD.bazel` has no reference to the new macro.
  `.write`'s guard was left untouched.

- **Noted but not changed**: this driver's own `Makefile` has the
  identical fragile `-I$(KERNEL_SRC)/$(M)/../../.../BSP/include`
  absolute-path pattern that broke `uwe5621ds`'s `WIFI/Makefile` on
  CoreELEC (see that tree's porting notes, round 8). This build got
  past compiling every file that needs those headers without a "file
  not found" error, which means CoreELEC's build harness is
  evidently supplying the correct path via the `UNISOC_BSP_INCLUDE`
  environment variable already (this `Makefile` already has an
  `ifneq ($(UNISOC_BSP_INCLUDE),)` fallback for exactly that), making
  the broken hardcoded path dead/unused in practice here. Left it
  alone rather than fix something with no observed failure -- if a
  future build environment doesn't set that variable and this
  surfaces as a real error, the fix is identical to the one already
  applied on the `uwe5621ds` side: switch to `-I$(src)/../...`.

## Fourth build-log round (real CoreELEC 5.15 kbuild build)

- **`modpost: ... undefined!`** for `get_wcn_bus_ops`,
  `marlin_set_wakeup`/`_sleep`, `start_marlin`/`stop_marlin`,
  `marlin_get_wcn_module_vendor`, `wcn_get_chip_model`,
  `marlin_get_ant_num` -- `sprdbt_tty.o` compiled and linked
  successfully (round three's `write_room` fix held); this is the
  same `KBUILD_EXTRA_SYMBOLS` gap fixed on the `uwe5621ds` tree's
  `WIFI/Makefile` in that tree's round twelve: `modpost` for this
  module never learns about the BSP module's exported symbols unless
  told to look at its `Module.symvers`.

  The fix here needed a different path expression than the
  `uwe5621ds` one, because the actual on-disk layout turned out to be
  different from what either driver's own Makefile assumed:
  `BSP/`, `WIFI/`, and `BT/tty-sdio/` all live as siblings directly
  under the package root (confirmed from the uploaded source tree and
  from the build log's literal `CURFOLDER=${PKG_BUILD}/BSP` in the
  `FAILED COMMAND` line), so `tty-sdio` is *not* a direct sibling of
  `BSP/` the way `uwe5621ds`'s `WIFI/` is -- a `$(src)/../BSP/`-style
  relative path would be wrong here. Used `$(CURFOLDER)/Module.symvers`
  instead: `CURFOLDER` is already explicitly set by the CoreELEC build
  invocation to point at the BSP module's directory (and the existing
  `-I$(CURFOLDER)/include` line already correctly resolves BSP's
  headers through it, which is why no header-not-found errors have
  shown up for this driver despite its own hardcoded fallback include
  path being just as broken as `uwe5621ds`'s WIFI/Makefile was -- see
  round three's notes on that). Verified all seven named symbols are
  genuinely `EXPORT_SYMBOL`'d in the BSP module's buildable sources
  (mostly `wcn_boot.c`, one in `wcn_bus.c`).

## Third round: sysfs WARN on real hardware boot (CoreELEC dmesg)

`mtty_probe` triggered a kernel `WARNING` on boot:

```
------------[ cut here ]------------
Attribute at: Invalid permissions 0777
WARNING: CPU: 0 PID: 443 at fs/sysfs/group.c:61 internal_create_group+0x1d0/0x3e4
...
Call trace:
 internal_create_group+0x1d0/0x3e4
 sysfs_create_group+0x24/0x34
 mtty_probe+0x210/0x2ec [sprdbt_tty ...]
```

Root cause, in `tty.c`: five `DEVICE_ATTR()` sysfs attributes
(`at`, `woble_set`, `ant_num`, `chipid`, `misc_node`) were declared
with mode `0777` (world read/write/execute), gated behind
`#define ALL_PER 1` -- a hardcoded, effectively-permanent `1` with a
`0660`-mode `#else` branch that could never actually be reached. The
kernel's own `DEVICE_ATTR()` macro has a build-time check,
`VERIFY_OCTAL_PERMISSIONS()`, specifically designed to *refuse to
compile* `0777` attributes -- this code went out of its way to defeat
that check with a local `#pragma push_macro("VERIFY_OCTAL_PERMISSIONS")`
/ redefine-to-no-op, rather than fix the underlying permission value.
At runtime, `sysfs_create_group()` independently re-checks and rejects
it with the `WARN()` seen above. The driver survives it (`mtty_probe`
completes, boot continues) but it was never a valid or intentional
permission mode -- it's a bug that happened to go unnoticed until a
kernel new enough to warn about it loudly.

Fixed by deleting the whole `ALL_PER`/`VERIFY_OCTAL_PERMISSIONS`
override block and declaring all five attributes at `0660` directly
(owner+group read/write) -- exactly what the driver's own dead `#else`
branch already intended, just without the override machinery forcing
past it.

## What I could not verify

Same caveat as the `uwe5621ds` tree: none of this has been
compile-tested, since I don't have your 5.15/6.2/6.12 kernel headers
or kleaf workspace available here. The TTY-core fixes (#1, #2 above)
are unconditional (no version guard, since the old APIs were removed
well before our 5.15 floor), so there's no cross-version threshold
risk there the way there was with `uwe5621ds`'s cfg80211/MLO fixes --
but I'd still treat this as a well-researched port rather than a
verified one until it's actually built.
