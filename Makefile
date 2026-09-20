TARGET := iphone:clang:latest:14.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = iRemove

iRemove_FILES = iRemoveApp.swift ContentView.swift RootHelper.m
iRemove_SWIFTFLAGS = -import-objc-header iRemove-Bridging-Header.h
iRemove_FRAMEWORKS = UIKit SwiftUI
iRemove_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
