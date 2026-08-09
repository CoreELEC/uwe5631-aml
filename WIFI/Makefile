PWD := $(shell pwd)
all_dependencies := driver


ifneq ($(UNISOC_BSP_INCLUDE),)
ccflags-y += -I$(UNISOC_BSP_INCLUDE)
endif
# $(src) is kbuild's standard "directory containing this Makefile"
# variable and resolves correctly regardless of whether M/KERNEL_SRC
# are passed as absolute or relative paths by the invoking build
# system. The previous $(KERNEL_SRC)/$(M)/../BSP/include/ form only
# worked when $(M) happened to be relative to $(KERNEL_SRC); passed
# as an absolute path (e.g. CoreELEC's build), it silently resolved
# to a nonexistent directory, causing "wcn_kcompat.h file not found" /
# "wcn_bus.h file not found" once any header in this driver needed to
# reach into the BSP module's include/ dir.
ccflags-y += -I$(src)/../BSP/include/

# CoreELEC's Amlogic 5.15 kernel has backported cfg80211's Linux 6.1
# MLO (multi-link operation) cfg80211_ops signature rework -- link_id
# parameters on add_key/del_key/set_default_key/stop_ap, and struct
# cfg80211_roam_info's links[] restructuring -- without a matching
# LINUX_VERSION_CODE bump, and additionally expects a 4th argument
# (beyond mainline's own 6.1+ signature) on cfg80211_ch_switch_notify().
# Both confirmed via real build failures. This Makefile (the
# traditional kbuild path) is only ever used for builds like
# CoreELEC's; the Android/AOSP target builds exclusively through
# BUILD.bazel's ddk_module (its own local_defines, never reads this
# Makefile's ccflags-y at all), so enabling these here by default
# cannot affect that target -- see the matching comment/default in
# BSP/Makefile for WCN_FILLDIR_RETURNS_INT, the same situation for a
# different (and, confusingly, oppositely-stale) API.
ccflags-y += -DWCN_CFG80211_HAS_MLO_LINK_ID
ccflags-y += -DWCN_CFG80211_CH_SWITCH_NOTIFY_HAS_PUNCT_BITMAP

# sprdwl_ng calls symbols EXPORT_SYMBOL'd by uwe5621_bsp_sdio
# (sprdwcn_bus_*, start_marlin/stop_marlin, marlin_get_wcn_chipid,
# get_wcn_bus_ops, and others). The top-level Makefile builds BSP
# before WIFI, so BSP's Module.symvers already exists by the time this
# Makefile runs -- but nothing told *this* module's modpost invocation
# to look at it, so it couldn't resolve any of those symbols at link
# time ("modpost: "sprdwcn_bus_..." [.../sprdwl_ng.ko] undefined!").
# KBUILD_EXTRA_SYMBOLS is the standard kbuild mechanism for exactly
# this situation: a second out-of-tree module in the same build that
# needs to resolve against a sibling module's exported symbol table
# (see Documentation/kbuild/modules.rst). $(src) is used rather than
# $(KERNEL_SRC)/$(M)/... for the same absolute-path-safety reason as
# the include path above.
KBUILD_EXTRA_SYMBOLS += $(src)/../BSP/Module.symvers

ifneq ($(UNISOC_WIFI_CUS_CONFIG),)
ccflags-y += -DCUSTOMIZE_WIFI_CFG_PATH=\"$(UNISOC_WIFI_CUS_CONFIG)\"
endif

ifneq ($(UNISOC_WIFI_MAC_FILE),)
ccflags-y += -DCUSTOMIZE_WIFI_MAC_FILE=\"$(UNISOC_WIFI_MAC_FILE)\"
endif

ifneq ($(UNISOC_MODULE_NAME),)
MODULE_NAME := $(UNISOC_MODULE_NAME)
else
MODULE_NAME := sprdwl_ng
endif

####add cflag######
ccflags-y += -DUWE5621_FTR 
ccflags-y += -DIBSS_SUPPORT -DIBSS_RSN_SUPPORT
ccflags-y += -DNAN_SUPPORT
ccflags-y += -DRTT_SUPPORT
ccflags-y += -DACS_SUPPORT -DRX_HW_CSUM
ccflags-y += -DWMMAC_WFA_CERTIFICATION
ccflags-y += -DCOMPAT_SAMPILE_CODE
ccflags-y += -DRND_MAC_SUPPORT
#ccflags-y += -DSOFTAP_HOOK
ccflags-y += -DATCMD_ASSERT
ccflags-y += -DTCPACK_DELAY_SUPPORT
#ccflags-y += -DTCPACK_DROP_DYNAMIC

#ccflags-y += -DDFS_MASTER
ccflags-y += -DRX_NAPI
ifneq ($(TARGET_BUILD_VARIANT),user)
ccflags-y += -DWL_CONFIG_DEBUG
endif
#ccflags-y += -DSPLIT_STACK
ccflags-y += -DSPRD_RX_THREAD
ccflags-y += -DOTT_UWE
ccflags-y += -DCP2_RESET_SUPPORT
ifeq ($(UNISOC_STA_SOFTAP_SCC_MODE),y)
ccflags-y += -DSTA_SOFTAP_SCC_MODE
endif

ccflags-y += -DPPPOE_LLC_SUPPORT
#ccflags-y += -DSPRDWL_TX_SELF
#ccflags-y += -DTCP_ACK_DROP_SUPPORT
ccflags-y += -DWOW_SUPPORT
#ccflags-y += -DCPUFREQ_UPDATE_SUPPORT
#ccflags-y += -DCUSTOM_REGDOMAIN
#####module name ###
obj-m += $(MODULE_NAME).o

#######add .o file#####
$(MODULE_NAME)-objs += main.o cfg80211.o txrx.o cmdevt.o npi.o msg.o work.o vendor.o \
				  tcp_ack.o mm.o reorder.o wl_core.o tx_msg.o rx_msg.o \
				  wl_intf.o qos.o dbg_ini_util.o reg_domain.o
$(MODULE_NAME)-objs += defrag.o
$(MODULE_NAME)-objs += ibss.o
$(MODULE_NAME)-objs += nan.o
$(MODULE_NAME)-objs += tracer.o
$(MODULE_NAME)-objs += rf_marlin3.o
$(MODULE_NAME)-objs += rtt.o
$(MODULE_NAME)-objs += api_version.o
$(MODULE_NAME)-objs += rnd_mac_addr.o
$(MODULE_NAME)-objs += debug.o
#$(MODULE_NAME)-objs += 11h.o

M ?= $(shell pwd)
all: $(all_dependencies)
driver: $(driver_dependencies)
	@echo build driver
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	$(RM) Module.markers
	$(RM) modules.order

modules:
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(KERNEL_SRC) M=$(M)  modules
