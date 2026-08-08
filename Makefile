all: modules

modules:
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(KERNEL_SRC) M=$(M)/BSP CFG_AML_WIFI_DEVICE_UWE5621=y modules
	$(CROSS_COMPILE)strip --strip-unneeded ${OUT_DIR}/$(M)/BSP/uwe5621_bsp_sdio.ko
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(KERNEL_SRC) M=$(M)/WIFI CFG_AML_WIFI_DEVICE_UWE5621=y modules
	$(CROSS_COMPILE)strip --strip-unneeded ${OUT_DIR}/$(M)/WIFI/sprdwl_ng.ko

modules_install:
	$(MAKE) INSTALL_MOD_STRIP=1 M=$(M)/BSP -C $(KERNEL_SRC) modules_install
	mkdir -p ${OUT_DIR}/../vendor_lib/modules
	cd ${OUT_DIR}/$(M); find -name "*.ko" -exec cp {} ${OUT_DIR}/../vendor_lib/modules/ \;

