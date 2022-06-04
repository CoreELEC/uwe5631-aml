# RELEASE

BOARD_HAVE_BLUETOOTH := true
BOARD_HAVE_BLUETOOTH_SPRD :=true
BOARD_HAVE_BLUETOOTH_UNISOC:= true

PRODUCT_COPY_FILES += frameworks/native/data/etc/android.hardware.bluetooth.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth.xml \
	                  frameworks/native/data/etc/android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml
PRODUCT_COPY_FILES += \
    vendor/amlogic/common/wifi_bt/wifi/unisoc/uwe5621/config/bt/bt_configure_pskey.ini:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth/uwe562x/bt_configure_pskey.ini \
    vendor/amlogic/common/wifi_bt/wifi/unisoc/uwe5621/config/bt/bt_configure_rf_marlin.ini:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth/uwe562x/bt_configure_rf_marlin.ini \
    vendor/amlogic/common/wifi_bt/wifi/unisoc/uwe5621/config/bt/bt_configure_rf_marlin3_2.ini:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth/uwe562x/bt_configure_rf_marlin3_2.ini \
    vendor/amlogic/common/wifi_bt/wifi/unisoc/uwe5621/config/bt/bt_configure_rf_marlin3_3.ini:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth/uwe562x/bt_configure_rf_marlin3_3.ini \
    vendor/amlogic/common/wifi_bt/wifi/unisoc/uwe5621/config/bt/bt_configure_rf_marlin3e_2.ini:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth/uwe562x/bt_configure_rf_marlin3e_2.ini \
    vendor/amlogic/common/wifi_bt/wifi/unisoc/uwe5621/config/bt/bt_configure_rf_marlin3e_3.ini:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth/uwe562x/bt_configure_rf_marlin3e_3.ini \
    #device/amlogic/common/tools/unisoc_driver.sh:$(TARGET_COPY_OUT_VENDOR)/bin/unisoc_driver.sh

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml

PRODUCT_PROPERTY_OVERRIDES += wc_transport.soc_initialized=0

PRODUCT_PACKAGES += \
    libbt-vendor_unisoc \
    bluetooth_unisoc.default \
    audio.a2dp.unisoc \
    bt_stack_unisoc.conf \
    bt_did_unisoc.conf \
    auto_pair_devlist_unisoc.conf \
    bdt_unisoc \
    libbt-utils_unisoc \
    libbt-hci_unisoc \
    btools_unisoc


