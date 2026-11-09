TARGET = iphone:clang:16.5:14.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Badoo

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BadooCapitalAI

BadooCapitalAI_FILES = \
    Sources/CapitalAPI.m \
    Sources/ConvoQueue.m \
    Sources/HapticTyper.m \
    Sources/Tweak.x

BadooCapitalAI_CFLAGS = -fobjc-arc \
    -Wno-unused-variable \
    -Wno-deprecated-declarations \
    -Wno-nullability-completeness \
    -fmodules \
    -fcxx-modules

include $(THEOS_MAKE_PATH)/tweak.mk
