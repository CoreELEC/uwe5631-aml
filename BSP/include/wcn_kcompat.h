/*
 * wcn_kcompat.h - small kernel-version compatibility shims added while
 * porting this driver from a Linux 5.4 (Android 11 GKI) tree to mainline
 * 5.15 / 6.2 / 6.12 kernels.
 *
 * Every macro here documents the kernel commit/version that forced it so
 * they can be revisited/pruned later without having to re-derive the
 * history.
 */
#ifndef __WCN_KCOMPAT_H__
#define __WCN_KCOMPAT_H__

#include <linux/version.h>
#include <linux/timekeeping.h>
#include <linux/proc_fs.h>
#include <linux/fs.h>

/*
 * getnstimeofday() was removed as part of the y2038 struct-timespec
 * cleanup (kernel 5.0, commit "y2038: remove obsolete jiffies interfaces").
 * ktime_get_real_ts64() has identical semantics and fills a
 * struct timespec64 (which callers must use instead of struct timespec).
 * It has existed since 3.17, so it's safe to call unconditionally here.
 */
#define wcn_getnstimeofday(ts) ktime_get_real_ts64(ts)

/*
 * PDE_DATA(inode) was renamed to pde_data(inode) in Linux 5.17
 * (commit 359745d78351 "proc: remove PDE_DATA() completely").
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 17, 0)
#define wcn_pde_data(inode) PDE_DATA(inode)
#else
#define wcn_pde_data(inode) pde_data(inode)
#endif

/*
 * class_create() dropped its 'owner' argument in Linux 6.4
 * (commit 1aaba11da9aa "driver core: class: remove module * from
 * class_create()").
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 4, 0)
#define wcn_class_create(name) class_create(THIS_MODULE, (name))
#else
#define wcn_class_create(name) class_create((name))
#endif

/*
 * set_fs()/get_fs()/KERNEL_DS were removed in Linux 5.10 (the "kernel
 * address space override" cleanup, commit 3d2054a888e2 and friends).
 * Code that used to do:
 *     fs_old = get_fs(); set_fs(KERNEL_DS);
 *     vfs_stat(kernel_path_string, &stat);
 *     set_fs(fs_old);
 * only to stat a file identified by a kernel-space path string, purely
 * to read its size, needs a replacement that doesn't reach for
 * vfs_getattr()/kern_path(): vfs_getattr() lives in the
 * "VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver" symbol
 * namespace and is off-limits to driver modules (modpost errors with
 * "uses symbol vfs_getattr ... but does not import it" -- and that
 * namespace is intentionally not meant to be imported by drivers).
 * Since both call sites in this driver only ever read `stat->size`,
 * the simplest portable fix is to open the file and read its inode
 * size directly -- no restricted-namespace symbols involved, and no
 * address-space override needed on any kernel version.
 */
static inline int wcn_vfs_stat(const char *path_str, struct kstat *stat)
{
	struct file *filp;

	filp = filp_open(path_str, O_RDONLY, 0);
	if (IS_ERR(filp))
		return PTR_ERR(filp);

	memset(stat, 0, sizeof(*stat));
	stat->size = i_size_read(file_inode(filp));

	filp_close(filp, NULL);

	return 0;
}

#endif /* __WCN_KCOMPAT_H__ */
