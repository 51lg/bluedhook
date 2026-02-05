# 针对 iOS 16.3 Rootless 必须开启
THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = bluedhook
# 这里的名字必须和文件夹里的 bluedhook.mm 一致
bluedhook_FILES = bluedhook.mm
# 开启相册保存功能必需的框架
bluedhook_FRAMEWORKS = UIKit Foundation CoreFoundation Photos
bluedhook_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk