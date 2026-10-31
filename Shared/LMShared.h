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

#define LMNotifyApply "com.xsxs18.lumenboard/apply"
#define LMNotifyClearCache "com.xsxs18.lumenboard/clear-cache"
#define LMNotifyRebuild "com.xsxs18.lumenboard/rebuild" // wipes the icon cache of iOS and resprings, nothing else
#define LMNotifyMapChanged "com.xsxs18.lumenboard/map-changed"
// state = (done << 32) | total, done == UINT32_MAX when SpringBoard is about to respring
#define LMNotifyProgress "com.xsxs18.lumenboard/progress"

// Config.plist
#define LMConfigEnabledThemes @"EnabledThemes" // theme folder names, first one wins
#define LMConfigUseSystemIconShape @"UseSystemIconShape"
#define LMConfigKeepIconsInDarkAndTinted @"KeepIconsInDarkAndTinted"
#define LMConfigCustomIconsRevision @"CustomIconsRevision" // changes whenever a custom icon is added, replaced or removed

// IconMap.plist
#define LMMapVersion 2 // 2: icon paths are jailbreak paths
#define LMMapIcons @"Icons" // lowercased bundle id -> icon
#define LMIconLight @"Light"
#define LMIconDark @"Dark"
#define LMIconTinted @"Tinted"
#define LMIconToken @"Token" // changes whenever the icon or the settings change
#define LMMapAppliedConfig @"AppliedConfig"

// Status-<name>.plist: what the tweak did in SpringBoard, in iconservicesagent and on the last apply. Shown on the diagnostics page.
#define LMStatusPath(name) [LMDataDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"Status-%@.plist", name]]
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
