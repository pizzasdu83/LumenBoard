#import "LMAppCatalog.h"
#import <objc/runtime.h>

@interface LSApplicationProxy : NSObject
- (NSString *)applicationIdentifier;
- (NSString *)localizedName;
- (NSArray *)appTags;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
@end

@interface UIImage (LMPrivateIcons)
+ (nullable UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@implementation LMAppInfo
@end

@implementation LMAppCatalog

+ (NSArray<LMAppInfo *> *)installedApps {
  NSMutableArray<LMAppInfo *> *apps = [NSMutableArray new];
  NSMutableSet<NSString *> *seen = [NSMutableSet new];
  Class workspaceClass = objc_getClass("LSApplicationWorkspace");
  for (LSApplicationProxy *proxy in [[workspaceClass defaultWorkspace] allInstalledApplications]) {
    NSString *bundleID = proxy.applicationIdentifier, *name = proxy.localizedName;
    if (![bundleID isKindOfClass:[NSString class]] || ![name isKindOfClass:[NSString class]] || !bundleID.length || !name.length) continue;
    if ([seen containsObject:bundleID.lowercaseString]) continue;
    // apps without an icon on the home screen
    if ([proxy respondsToSelector:@selector(appTags)] && [[proxy appTags] containsObject:@"hidden"]) continue;
    [seen addObject:bundleID.lowercaseString];
    LMAppInfo *app = [LMAppInfo new];
    app.bundleID = bundleID;
    app.name = name;
    [apps addObject:app];
  }
  [apps sortUsingComparator:^NSComparisonResult(LMAppInfo *a, LMAppInfo *b) {
    return [a.name localizedCaseInsensitiveCompare:b.name];
  }];
  return apps;
}

+ (UIImage *)iconForBundleID:(NSString *)bundleID {
  static NSCache<NSString *, UIImage *> *cache;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    cache = [NSCache new];
  });
  UIImage *cached = [cache objectForKey:bundleID];
  if (cached) return cached;
  if (![UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) return nil;
  UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2 scale:[UIScreen mainScreen].scale];
  if (icon) [cache setObject:icon forKey:bundleID];
  return icon;
}

@end
