#pragma once

#import <Foundation/Foundation.h>
#include <unistd.h>

#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#include <roothide.h>
#endif

// jailbreak path -> real path (/var/jb/... on rootless, inside the random jbroot folder on roothide)
static inline NSString *LMRootPath(NSString *path) {
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
  return jbroot(path);
#else
  static NSString *root;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    root = (access("/var/jb", F_OK) == 0) ? @"/var/jb" : @"";
  });
  return [root stringByAppendingString:path];
#endif
}

// real path -> jailbreak path. Used for paths we save, roothide renames the jbroot folder on every jailbreak.
static inline NSString *LMJailbreakPath(NSString *path) {
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
  return rootfs(path);
#else
  NSString *root = LMRootPath(@"");
  return (root.length && [path hasPrefix:[root stringByAppendingString:@"/"]]) ? [path substringFromIndex:root.length] : path;
#endif
}

#define LMThemesDirectory LMRootPath(@"/Library/Themes")
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#define LMThemesDirectoryDisplayName @"/Library/Themes"
#else
#define LMThemesDirectoryDisplayName LMThemesDirectory
#endif

// Config.plist (app) and IconMap.plist (SpringBoard). Not in /var/mobile/Library/Preferences because
// iconservicesagent is sandboxed and can only read from the jailbreak folder.
#define LMDataDirectory LMRootPath(@"/var/mobile/Library/LumenBoard")
#define LMConfigPath [LMDataDirectory stringByAppendingPathComponent:@"Config.plist"]
#define LMIconMapPath [LMDataDirectory stringByAppendingPathComponent:@"IconMap.plist"]
// icons picked in the app: CustomIcons/<lowercased bundle id>.png. They win over every theme.
#define LMCustomIconsDirectory [LMDataDirectory stringByAppendingPathComponent:@"CustomIcons"]
// images picked as icon background in the app
#define LMBackgroundsDirectory [LMDataDirectory stringByAppendingPathComponent:@"Backgrounds"]
// themes imported from a zip in the app, same layout as /Library/Themes (that folder belongs to root, the app can't write there)
#define LMImportedThemesDirectory [LMDataDirectory stringByAppendingPathComponent:@"ImportedThemes"]

#define LMNotifyApply "com.xsxs18.lumenboard/apply"
#define LMNotifyRebuild "com.xsxs18.lumenboard/rebuild" // wipes the icon cache of iOS and resprings, nothing else
#define LMNotifyMapChanged "com.xsxs18.lumenboard/map-changed"
// state = (done << 32) | total, done == UINT32_MAX when SpringBoard is about to respring
#define LMNotifyProgress "com.xsxs18.lumenboard/progress"

// Config.plist
#define LMConfigEnabledThemes @"EnabledThemes" // theme folder names, first one wins
#define LMConfigUseSystemIconShape @"UseSystemIconShape" // before 1.1.0, IconShape replaces it
#define LMConfigIconShape @"IconShape" // one of LMIconShape*
#define LMConfigIconEffects @"IconEffects" // underlays/overlays from themes (AnemoneEffects), on when missing
#define LMConfigKeepIconsInDarkAndTinted @"KeepIconsInDarkAndTinted"
#define LMConfigCustomIconsRevision @"CustomIconsRevision" // changes whenever a custom icon is added, replaced or removed
// what goes behind the theme icons, light and dark mode each have their own: { Mode: none | color | gradient | image,
// Color, Color2: "#RRGGBB", Angle: degrees (0 = left to right, 90 = top to bottom), Image: file name in LMBackgroundsDirectory }
#define LMConfigBackgroundLight @"BackgroundLight"
#define LMConfigBackgroundDark @"BackgroundDark"
#define LMMapBackground @"Background" // in the icon map: { Light: {...}, Dark: {...} }, Image is a jailbreak path there
#define LMConfigShapeApps @"IOSShapeApps" // lowercased bundle ids whose icon gets the iOS icon shape, even if the setting is off
#define LMConfigShapeThemes @"IOSShapeThemes" // theme folder names whose icons all get the iOS icon shape

// Icon shapes. Theme and iOS only change theme icons, the others change every app icon.
#define LMIconShapeTheme @"theme" // theme icons as drawn
#define LMIconShapeSystem @"system" // iOS mask
#define LMIconShapeCircle @"circle"
#define LMIconShapeRounded @"rounded"
#define LMIconShapeSquare @"square"
#define LMIconShapeTeardrop @"teardrop"
#define LMIconShapeThemeMask @"mask" // AppIconMask png of an active theme

static inline NSArray<NSString *> *LMIconShapes(void) {
  return @[LMIconShapeTheme, LMIconShapeSystem, LMIconShapeCircle, LMIconShapeRounded, LMIconShapeSquare, LMIconShapeTeardrop, LMIconShapeThemeMask];
}

// IconShape from a config, also for configs written before 1.1.0
static inline NSString *LMIconShapeFromConfig(NSDictionary *config) {
  NSString *shape = config[LMConfigIconShape];
  if ([shape isKindOfClass:[NSString class]] && [LMIconShapes() containsObject:shape]) return shape;
  // configs before 1.1.0 have one switch for the iOS shape, a new config has the iOS shape
  id legacy = config[LMConfigUseSystemIconShape];
  return (legacy && ![legacy boolValue]) ? LMIconShapeTheme : LMIconShapeSystem;
}

static inline BOOL LMIconEffectsFromConfig(NSDictionary *config) {
  NSNumber *effects = config[LMConfigIconEffects];
  return [effects isKindOfClass:[NSNumber class]] ? effects.boolValue : YES;
}

// IconMap.plist
#define LMMapVersion 2 // 2: icon paths are jailbreak paths
#define LMMapIcons @"Icons" // lowercased bundle id -> icon
#define LMIconLight @"Light"
#define LMIconDark @"Dark"
#define LMIconTinted @"Tinted"
#define LMIconToken @"Token" // changes whenever the icon or the settings change
#define LMIconTheme @"Theme" // only while resolving: the theme folder an icon comes from, not in the icon map
#define LMIconSystemShape @"SystemShape" // YES: iOS applies its mask. Missing in maps before 1.1.0, then the map's UseSystemIconShape counts
#define LMIconStock @"Stock" // the app's own icon with the shape/effects, not a theme icon
#define LMMapAppliedConfig @"AppliedConfig"

// icons with the shape and effects drawn in, made by SpringBoard on Apply
#define LMComposedDirectory [LMDataDirectory stringByAppendingPathComponent:@"Composed"]

// Status-<name>.plist: what the tweak did in SpringBoard, in iconservicesagent and on the last apply. Shown on the diagnostics page.
#define LMStatusPath(name) [LMDataDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"Status-%@.plist", name]]
// one line that changes whenever the background changes how an icon looks
static inline NSString *LMBackgroundSignature(NSDictionary *background) {
  if (![background isKindOfClass:[NSDictionary class]]) return @"-";
  return [NSString stringWithFormat:@"%@,%@,%@,%@,%@", background[@"Mode"] ? : @"", background[@"Color"] ? : @"", background[@"Color2"] ? : @"", background[@"Angle"] ? : @"", background[@"Image"] ? : @""];
}

// the folder where iOS keeps the rendered app icons
#define LMSystemIconsCacheFolder @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.iconscache/Library/Caches"

// LumenBoardHelper is a root LaunchDaemon: deletes the contents of LMSystemIconsCacheFolder (the folder belongs to a system user)
// when it gets LMNotifyHelperWipe, writes what happened to LMHelperResultPath and posts LMNotifyHelperDone
#define LMNotifyHelperWipe "com.xsxs18.lumenboard/helper-wipe"
#define LMNotifyHelperDone "com.xsxs18.lumenboard/helper-done"
#define LMHelperResultPath [LMDataDirectory stringByAppendingPathComponent:@"RebuildHelper.txt"]

// Deletes everything in LMSystemIconsCacheFolder and says what happened:
// Found, Deleted, Failed, Remaining (what's still there afterwards) and Error (the first thing that went wrong)
static inline NSDictionary *LMWipeSystemIconsCache(void) {
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSMutableDictionary *result = [NSMutableDictionary new];
  NSError *listError;
  NSArray *items = [fileManager contentsOfDirectoryAtPath:LMSystemIconsCacheFolder error:&listError];
  if (!items) {
    result[@"Found"] = @0;
    result[@"Deleted"] = @0;
    result[@"Failed"] = @0;
    result[@"Remaining"] = @0;
    result[@"Error"] = listError.localizedDescription ? : @"can't read the folder";
    return result;
  }
  NSUInteger deleted = 0, failed = 0;
  for (NSString *item in items) {
    NSError *itemError;
    if ([fileManager removeItemAtPath:[LMSystemIconsCacheFolder stringByAppendingPathComponent:item] error:&itemError]) {
      deleted++;
    } else {
      failed++;
      if (!result[@"Error"]) result[@"Error"] = [NSString stringWithFormat:@"%@: %@", item, itemError.localizedDescription ? : @"unknown error"];
    }
  }
  result[@"Found"] = @(items.count);
  result[@"Deleted"] = @(deleted);
  result[@"Failed"] = @(failed);
  result[@"Remaining"] = @([[fileManager contentsOfDirectoryAtPath:LMSystemIconsCacheFolder error:nil] count]);
  return result;
}

#define LMStatusLoaded @"Loaded"
#define LMStatusUpdated @"Updated"
#define LMStatusHooksInstalled @"HooksInstalled"
#define LMStatusAgentRendersThemes @"AgentRendersThemes" // NO: SpringBoard renders the theme icons itself
#define LMStatusMapIcons @"MapIcons"
#define LMStatusCounters @"Counters"
#define LMStatusEvents @"Events"
