ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = QATestingUtils
QATestingUtils_FILES = Tweak.x
QATestingUtils_CFLAGS = -fobjc-arc
QATestingUtils_FRAMEWORKS = UIKit Foundation StoreKit

include $(THEOS_MAKE_PATH)/tweak.mk
