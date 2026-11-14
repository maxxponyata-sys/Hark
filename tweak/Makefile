TARGET := iphone:clang:10.3:10.0
ARCHS = armv7 arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HarkSiri

HarkSiri_FILES = Tweak.x
HarkSiri_CFLAGS = -fobjc-arc
HarkSiri_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
