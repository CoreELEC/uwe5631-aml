
# ccflags-y += -DDEBUG
# ccflags-y += -DKERNEL_VERSION_414
PWD := $(shell pwd)
CURFOLDER ?= $(pwd)

#ccflags-y += -I$(srctree)/drivers/net/wireless/uwe5622/sprdwcn/include
ccflags-y += -I$(CURFOLDER)/include
#ccflags-y += -DUSE_DTS

# sprdbt_tty calls symbols EXPORT_SYMBOL'd by the BSP module
# (get_wcn_bus_ops, start_marlin/stop_marlin, marlin_set_wakeup/_sleep,
# marlin_get_wcn_module_vendor, wcn_get_chip_model, marlin_get_ant_num,
# and others) -- same underlying gap as uwe5621ds's WIFI/Makefile fix:
# modpost for this module never learns about the BSP module's exported
# symbol table unless told to look at its Module.symvers.
# KBUILD_EXTRA_SYMBOLS is kbuild's mechanism for exactly this (see
# Documentation/kbuild/modules.rst).
#
# $(CURFOLDER) is used rather than a hardcoded relative path because
# the actual CoreELEC build invocation already sets it explicitly to
# the BSP module's directory (CURFOLDER=${PKG_BUILD}/BSP, confirmed
# via the real "FAILED COMMAND" line in the build log, and by the
# -I$(CURFOLDER)/include line above already correctly resolving BSP's
# headers) -- BT/tty-sdio is nested under a BT/ subdirectory, not a
# direct sibling of BSP/, so a $(src)/../BSP/-style relative path
# (as used in uwe5621ds's WIFI/Makefile) would be wrong here. If
# CURFOLDER isn't set by the invoking build (it defaults to this
# Makefile's own directory), this line points at a Module.symvers
# that doesn't exist there -- kbuild generally tolerates a missing
# KBUILD_EXTRA_SYMBOLS path without hard-failing, and in that
# fallback scenario the -I$(CURFOLDER)/include line above would
# already be broken too (same root cause), so this isn't introducing
# a new failure mode.
KBUILD_EXTRA_SYMBOLS += $(CURFOLDER)/Module.symvers

ifneq ($(UNISOC_BSP_INCLUDE),)
ccflags-y += -I$(UNISOC_BSP_INCLUDE)
endif
ccflags-y += -I$(KERNEL_SRC)/$(M)/../../../../../../wifi_driver/unisoc/uwe5621/BSP/include
ccflags-y += -DWOBLE_TYPE="\"disable\""
#ccflags-y += -DWOBLE_TYPE="\"chuangwei\""

# At least one target kernel (CoreELEC's Amlogic 5.15 kernel) has
# backported the struct tty_operations::write_room return-type change
# (int -> unsigned int, normally part of a Linux 6.6.1 tty-core
# cleanup) into an otherwise pre-6.6.1 tree -- confirmed via a real
# build failure. This Makefile (the traditional kbuild path) is only
# ever used for builds like CoreELEC's; the Android/AOSP target builds
# exclusively through BUILD.bazel's ddk_module (its own local_defines,
# never reads this Makefile's ccflags-y at all), so enabling this here
# by default cannot affect that target -- see the matching
# WCN_FILLDIR_RETURNS_INT/WCN_CFG80211_HAS_MLO_LINK_ID defaults in the
# uwe5621ds tree's BSP/Makefile and WIFI/Makefile for the same
# situation on other APIs.
ccflags-y += -DWCN_TTY_WRITE_ROOM_RETURNS_UINT

sprdbt_tty-objs := \
	tty.o \
	rfkill.o \
	lpm.o \
	debug.o \
	sdio.o \
	sitm.o \
	hci.o \
	debug.o

obj-m += sprdbt_tty.o

modules:
	@echo cross_comple = $(CROSS_COMPILE)
	@echo CFLAGS = $(CFLAGS)
	@echo EXTRA_CFLAGS = $(EXTRA_CFLAGS)
	@echo kernel src= $(KERNEL_SRC)
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(KERNEL_SRC) M=$(M) modules

modules_install:
	@$(MAKE) INSTALL_MOD_STRIP=1 M=$(M) -C $(KERNEL_SRC) modules_install
	mkdir -p ${OUT_DIR}/../vendor_lib/modules
	cd ${OUT_DIR}/$(M)/; find -name "*.ko" -exec cp {} ${OUT_DIR}/../vendor_lib/modules/ \;
