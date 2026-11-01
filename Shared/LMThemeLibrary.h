#import "LMShared.h"

NS_ASSUME_NONNULL_BEGIN

// Reads theme folders in the formats SnowBoard, Anemone and WinterBoard use:
//   Theme.theme/IconBundles/<bundle id>[-large][-dark|-tinted][@2x|@3x][~iphone|~ipad].png
//   Theme.theme/Icons/<App Name>.png
@interface LMThemeLibrary : NSObject

// folder names in /Library/Themes, sorted by display name
+ (NSArray<NSString *> *)installedThemes;
// "Viola.theme" -> "Viola"
+ (NSString *)displayNameForTheme:(NSString *)theme;
// lowercased bundle identifier -> @{ LMIconLight: path, LMIconDark: path, LMIconTinted: path }
+ (NSDictionary<NSString *, NSDictionary *> *)iconsInTheme:(NSString *)theme;
// same, keyed by lowercased app name ("Icons" folder)
+ (NSDictionary<NSString *, NSDictionary *> *)iconsByAppNameInTheme:(NSString *)theme;
// icons picked in the app (CustomIcons folder), same format as iconsInTheme:
+ (NSDictionary<NSString *, NSDictionary *> *)customIcons;
// custom icons first, then first theme wins, IconBundles before Icons. appNames: app name -> bundle ids
+ (NSDictionary<NSString *, NSDictionary *> *)resolvedIconsForThemes:(NSArray<NSString *> *)themes appNames:(nullable NSDictionary<NSString *, NSArray<NSString *> *> *)appNames;
// why the theme's icons couldn't be listed last time, nil if they could
+ (nullable NSString *)readErrorForTheme:(NSString *)theme;
// forget cached folder listings (after themes were installed or removed)
+ (void)invalidate;
+ (void)invalidateTheme:(NSString *)theme;
// where a theme lives: the themes folder, or the folder of the themes imported in the app
+ (NSString *)directoryForTheme:(NSString *)theme;
+ (BOOL)isImportedTheme:(NSString *)theme;
+ (void)invalidateCustomIcons;

@end

NS_ASSUME_NONNULL_END
