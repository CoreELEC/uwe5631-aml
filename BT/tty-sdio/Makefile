
# ccflags-y += -DDEBUG
# ccflags-y += -DKERNEL_VERSION_414
PWD := $(shell pwd)
CURFOLDER ?= $(pwd)

KBUILD_EXTRA_SYMBOLS := $(M)/../../BSP/Module.symvers

#ccflags-y += -I$(srctree)/drivers/net/wireless/uwe5622/sprdwcn/include
ccflags-y += -I$(CURFOLDER)/include
#ccflags-y += -DUSE_DTS
ccflags-y +=  -Wno-uninitialized

ifneq ($(UNISOC_BSP_INCLUDE),)
ccflags-y += -I$(UNISOC_BSP_INCLUDE)
endif
#add by amlogic
ccflags-y += -I$(KERNEL_SRC)/../vendor/wifi_driver/unisoc/uwe5621/BSP/include

#ccflags-y += -DWOBLE_TYPE="\"disable\""
ccflags-y += -DWOBLE_TYPE="\"demo\""
#ccflags-y += -DUNISOC_AMLOGIC_SUSPEND

# support assert bt reset
# ccflags-y += -DCP2_RESET_SUPPORT

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

