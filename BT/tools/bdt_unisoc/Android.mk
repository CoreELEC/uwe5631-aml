LOCAL_PATH:= $(call my-dir)

include $(CLEAR_VARS)

LOCAL_SRC_FILES:=     \
    bdt_unisoc.c

LOCAL_C_INCLUDES := vendor/amlogic/common/wifi_bt/bluetooth/unisoc/tools/btsuite/main/include

LOCAL_MODULE:= bdt_unisoc
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_SHARED_LIBRARIES +=
LOCAL_PROPRIETARY_MODULE := true

include $(BUILD_EXECUTABLE)
