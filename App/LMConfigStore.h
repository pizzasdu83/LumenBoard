#import "../Shared/LMShared.h"

NS_ASSUME_NONNULL_BEGIN

// Config.plist, the only thing the app writes. SpringBoard turns it into the icon map on "Apply".
@interface LMConfigStore : NSObject

+ (instancetype)sharedStore;
// theme folder names, highest priority first
@property (nonatomic, copy) NSArray<NSString *> *enabledThemes;
@property (nonatomic) BOOL useSystemIconShape;
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
