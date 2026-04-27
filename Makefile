DEBUG = 0
FINALPACKAGE = 1
ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.5

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WAIconPicker

WAIconPicker_FILES = Tweak.xm
WAIconPicker_CFLAGS = -fobjc-arc
WAIconPicker_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk