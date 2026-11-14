TARGET := iphone:clang:10.3:10.0
ARCHS = armv7 arm64
INSTALL_TARGET_PROCESSES = Hark

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Hark

Hark_FILES = $(wildcard Sources/*.m)
Hark_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore AVFoundation Speech CoreLocation CoreTelephony EventKit MediaPlayer SystemConfiguration Security
Hark_CFLAGS = -fobjc-arc -ISources -Wno-deprecated-declarations
Hark_CODESIGN_FLAGS = -S

include $(THEOS_MAKE_PATH)/application.mk
