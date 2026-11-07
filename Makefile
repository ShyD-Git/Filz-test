TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES = Filza

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FilzaQAMock

FilzaQAMock_FILES = Tweak.x
FilzaQAMock_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
