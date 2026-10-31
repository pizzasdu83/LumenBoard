#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LMAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@end

// The apps installed on the device, read from LaunchServices.
@interface LMAppCatalog : NSObject

// apps the user can see, sorted by name. Can take a moment, avoid the main thread.
+ (NSArray<LMAppInfo *> *)installedApps;
// the icon of the app as it is shown right now, nil if iOS doesn't give it
+ (nullable UIImage *)iconForBundleID:(NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END
