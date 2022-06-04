ifeq ($(BOARD_HAVE_BLUETOOTH_UNISOC),true)
LOCAL_PATH := $(call my-dir)
include $(call all-subdir-makefiles)
endif
