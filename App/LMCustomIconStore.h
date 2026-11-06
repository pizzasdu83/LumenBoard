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
// any png: decodes only what the thumbnail needs, theme icons are often 1024 px
+ (nullable UIImage *)thumbnailForPath:(NSString *)path pixels:(CGFloat)pixels;
// the icon over the background of the settings (a config background: Mode, Color, Color2, Angle, Image), like the home screen draws it.
// The background is the same for every icon, nil or none: the icon as it is.
+ (UIImage *)image:(UIImage *)image overBackground:(nullable NSDictionary *)background;
// the image clipped to the iOS icon shape (the continuous corners of a home screen icon)
+ (UIImage *)squircleImage:(UIImage *)image;

@end

NS_ASSUME_NONNULL_END
