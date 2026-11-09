ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BadooCapitalAI

BadooCapitalAI_FILES = \
	Sources/CapitalAPI.m \
	Sources/ConvoQueue.m \
	Sources/HapticTyper.m \
	Sources/BCEngine.m \
	Sources/Tweak.x

BadooCapitalAI_CFLAGS     = -fobjc-arc \
                             -Wno-unused-variable \
                             -Wno-deprecated-declarations
BadooCapitalAI_LDFLAGS    = -Wl,-segalign,4000
BadooCapitalAI_FRAMEWORKS = UIKit Foundation CoreHaptics

include $(THEOS_MAKE_PATH)/tweak.mk
