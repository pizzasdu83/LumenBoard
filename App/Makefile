include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LumenBoard
LumenBoard_FILES = main.m LMAppDelegate.m LMConfigStore.m LMThemesViewController.m LMSettingsViewController.m LMApplyViewController.m LMDiagnosticsViewController.m LMShapeViewController.m LMCustomIconsViewController.m LMAppPickerViewController.m LMAppCatalog.m LMCustomIconStore.m LMZipImporter.m LMDebImporter.m LMBackgroundViewController.m ../Shared/LMThemeLibrary.m
LumenBoard_FRAMEWORKS = UIKit QuartzCore ImageIO UniformTypeIdentifiers
LumenBoard_LIBRARIES = z
LumenBoard_CFLAGS = -fobjc-arc -Wall -Wno-deprecated-declarations -Wno-unguarded-availability-new
LumenBoard_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
