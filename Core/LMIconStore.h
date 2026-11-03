#import "../Shared/LMShared.h"

NS_ASSUME_NONNULL_BEGIN

// IconMap.plist, loaded on first use
@interface LMIconStore : NSObject

+ (instancetype)sharedStore;
// nil when the app isn't themed
- (nullable NSDictionary *)iconForBundleIdentifier:(nullable NSString *)bundleIdentifier;
@property (nonatomic, readonly) NSUInteger themedIconCount;
@property (nonatomic, readonly) BOOL usesSystemIconShape;
@property (nonatomic, readonly) BOOL keepsIconsInDarkAndTinted;
// what goes behind the theme icons: 0 = light, 1 = dark, anything else (tinted...) has none. nil when there is none.
- (nullable NSDictionary *)backgroundForAppearance:(long long)appearance;
// re-read IconMap.plist on next use
- (void)reload;
// reload right away if IconMap.plist was replaced since it was read (one stat() call)
- (void)reloadIfMapChanged;

@end

NS_ASSUME_NONNULL_END
