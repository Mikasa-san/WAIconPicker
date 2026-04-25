DEBUG = 0
FINALPACKAGE = 1
ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WAIconPicker

WAIconPicker_FILES = Tweak.xm
WAIconPicker_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk