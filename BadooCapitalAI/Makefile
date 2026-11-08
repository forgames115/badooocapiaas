ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BadooCapitalAI

BadooCapitalAI_FILES = \
	Sources/Tweak.x \
	Sources/CapitalAPI.m \
	Sources/ConvoQueue.m \
	Sources/HapticTyper.m

BadooCapitalAI_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-nullability-completeness
BadooCapitalAI_FRAMEWORKS = UIKit Foundation
BadooCapitalAI_PRIVATE_FRAMEWORKS = CoreHaptics

include $(THEOS_MAKE_PATH)/tweak.mk
