#import "LMCustomIconStore.h"
#import "LMConfigStore.h"
#import "LMAppDelegate.h"
#import "../Shared/LMThemeLibrary.h"
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#include <sys/stat.h>

static const CGFloat LMCustomIconPixels = 1024;

// the middle of the image, filled to a square (keeps transparency)
static UIImage *LMSquareIcon(UIImage *image) {
  CGSize size = image.size;
  if (size.width <= 0 || size.height <= 0) return nil;
  CGFloat side = LMCustomIconPixels;
  CGFloat factor = MAX(side / size.width, side / size.height);
  CGSize drawn = CGSizeMake(size.width * factor, size.height * factor);
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
  format.scale = 1;
  format.opaque = NO;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:format];
  return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    [image drawInRect:CGRectMake((side - drawn.width) / 2, (side - drawn.height) / 2, drawn.width, drawn.height)];
  }];
}

@implementation LMCustomIconStore

+ (NSString *)pathForBundleID:(NSString *)bundleID {
  return [LMCustomIconsDirectory stringByAppendingPathComponent:[bundleID.lowercaseString stringByAppendingPathExtension:@"png"]];
}

+ (NSArray<NSString *> *)bundleIDs {
  NSMutableArray *bundleIDs = [NSMutableArray new];
  for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:LMCustomIconsDirectory error:nil]) {
    if ([file hasPrefix:@"."] || ![file.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
    [bundleIDs addObject:file.stringByDeletingPathExtension.lowercaseString];
  }
  return bundleIDs;
}

+ (BOOL)hasIconForBundleID:(NSString *)bundleID {
  return [[NSFileManager defaultManager] fileExistsAtPath:[self pathForBundleID:bundleID]];
}

// the config gets a new revision so the app and SpringBoard know there is something to apply
+ (BOOL)iconsDidChange:(NSError **)error {
  [LMThemeLibrary invalidateCustomIcons];
  return [[LMConfigStore sharedStore] customIconsDidChange:error];
}

+ (BOOL)setImage:(UIImage *)image forBundleID:(NSString *)bundleID error:(NSError **)error {
  UIImage *square = LMSquareIcon(image);
  NSData *data = square ? UIImagePNGRepresentation(square) : nil;
  if (!data) {
    if (error) *error = [NSError errorWithDomain:@"LumenBoard" code:1 userInfo:@{ NSLocalizedDescriptionKey : LMLocalized(@"This image can't be used as an icon.") }];
    return NO;
  }
  NSString *directory = LMCustomIconsDirectory, *path = [self pathForBundleID:bundleID];
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
  if (![data writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
  // iconservicesagent and SpringBoard only read them
  chmod(directory.fileSystemRepresentation, 0755);
  chmod(path.fileSystemRepresentation, 0644);
  return [self iconsDidChange:error];
}

+ (BOOL)removeIconForBundleID:(NSString *)bundleID error:(NSError **)error {
  NSString *path = [self pathForBundleID:bundleID];
  if ([[NSFileManager defaultManager] fileExistsAtPath:path] && ![[NSFileManager defaultManager] removeItemAtPath:path error:error]) return NO;
  return [self iconsDidChange:error];
}

+ (UIImage *)thumbnailForBundleID:(NSString *)bundleID pixels:(CGFloat)pixels {
  return [self thumbnailForPath:[self pathForBundleID:bundleID] pixels:pixels];
}

+ (UIImage *)squircleImage:(UIImage *)image {
  CGFloat side = MAX(image.size.width, image.size.height);
  if (side <= 0) return image;
  // a layer with continuous corners is what iOS uses for its icons, a plain rounded rect is a bit different
  CALayer *layer = [CALayer layer];
  layer.frame = CGRectMake(0, 0, image.size.width, image.size.height);
  layer.contents = (__bridge id)image.CGImage;
  layer.contentsGravity = kCAGravityResizeAspectFill;
  layer.cornerRadius = MIN(image.size.width, image.size.height) * 0.2237;
  layer.cornerCurve = kCACornerCurveContinuous;
  layer.masksToBounds = YES;
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
  format.scale = image.scale;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format];
  return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    [layer renderInContext:context.CGContext];
  }];
}

+ (UIImage *)thumbnailForPath:(NSString *)path pixels:(CGFloat)pixels {
  static NSCache<NSString *, UIImage *> *cache;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    cache = [NSCache new];
  });
  if (!path.length) return nil;
  struct stat info;
  if (stat(path.fileSystemRepresentation, &info) != 0) return nil;
  // a replaced image has a new modification time
  NSString *key = [NSString stringWithFormat:@"%@|%lld.%ld|%d", path, (long long)info.st_mtimespec.tv_sec, (long)info.st_mtimespec.tv_nsec, (int)pixels];
  UIImage *cached = [cache objectForKey:key];
  if (cached) return cached;

  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path isDirectory:NO], NULL);
  if (!source) return nil;
  NSDictionary *options = @{
    (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
    (__bridge id)kCGImageSourceCreateThumbnailWithTransform : @YES,
    (__bridge id)kCGImageSourceThumbnailMaxPixelSize : @(pixels),
  };
  CGImageRef image = CGImageSourceGetCount(source) ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options) : NULL;
  CFRelease(source);
  if (!image) return nil;
  UIImage *thumbnail = [UIImage imageWithCGImage:image];
  CGImageRelease(image);
  if (thumbnail) [cache setObject:thumbnail forKey:key];
  return thumbnail;
}

@end
