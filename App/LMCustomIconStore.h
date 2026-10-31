#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// The icons picked in the app. One square PNG per app in CustomIcons/<lowercased bundle id>.png,
// SpringBoard reads them when the icon map is built (Apply).
@interface LMCustomIconStore : NSObject

// lowercased bundle identifiers of the apps that have a custom icon
+ (NSArray<NSString *> *)bundleIDs;
+ (BOOL)hasIconForBundleID:(NSString *)bundleID;
// cropped to a square, scaled to 1024 px and saved as PNG
+ (BOOL)setImage:(UIImage *)image forBundleID:(NSString *)bundleID error:(NSError **)error;
+ (BOOL)removeIconForBundleID:(NSString *)bundleID error:(NSError **)error;
+ (nullable UIImage *)thumbnailForBundleID:(NSString *)bundleID pixels:(CGFloat)pixels;

@end

NS_ASSUME_NONNULL_END
