#import "../Shared/LMShared.h"

NS_ASSUME_NONNULL_BEGIN

// Config.plist, the only thing the app writes. SpringBoard turns it into the icon map on "Apply".
@interface LMConfigStore : NSObject

+ (instancetype)sharedStore;
// theme folder names, highest priority first
@property (nonatomic, copy) NSArray<NSString *> *enabledThemes;
// LMIconShape*
@property (nonatomic, copy) NSString *iconShape;
// underlays/overlays from the active themes
@property (nonatomic) BOOL iconEffects;
// With the icon shape "Theme's own shape": lowercased bundle ids whose icon gets the iOS shape anyway
@property (nonatomic, copy) NSArray<NSString *> *shapeApps;
// With the icon shape "Theme's own shape": theme folder names whose icons all get the iOS shape
@property (nonatomic, copy) NSArray<NSString *> *shapeThemes;
// the background behind the icons with the iOS shape in light and dark mode, see LMConfigBackgroundLight. Empty: none.
@property (nonatomic, copy) NSDictionary *backgroundLight;
@property (nonatomic, copy) NSDictionary *backgroundDark;
@property (nonatomic) BOOL keepIconsInDarkAndTinted;
// changes whenever a custom icon is added, replaced or removed, so "Apply" knows there is something to do
@property (nonatomic, copy, readonly) NSString *customIconsRevision;
// call after the CustomIcons folder changed, saves the config
- (BOOL)customIconsDidChange:(NSError **)error;
// changed since the last apply
@property (nonatomic, readonly) BOOL hasUnappliedChanges;

- (BOOL)save:(NSError **)error;
- (void)markApplied;

@end

NS_ASSUME_NONNULL_END
