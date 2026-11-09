TARGET = iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Badoo

# Rootless pre Dopamine
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BadooCapitalAI
BadooCapitalAI_FILES = \
    Sources/CapitalAPI.m \
    Sources/ConvoQueue.m \
    Sources/HapticTyper.m \
    Sources/Tweak.x

# Pridané -Wno-arc-performSelector-leaks na opravu chyby
BadooCapitalAI_CFLAGS = -fobjc-arc \
    -Wno-unused-variable \
    -Wno-deprecated-declarations \
    -Wno-nullability-completeness \
    -Wno-arc-performSelector-leaks \
    -fmodules \
    -fcxx-modules

include $(THEOS_MAKE_PATH)/tweak.mk
