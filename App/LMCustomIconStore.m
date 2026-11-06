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

static UIColor *LMStoreColorFromHex(id hex) {
  if (![hex isKindOfClass:[NSString class]]) return nil;
  NSString *digits = [hex hasPrefix:@"#"] ? [hex substringFromIndex:1] : hex;
  unsigned long long value = 0;
  if ((digits.length != 6 && digits.length != 8) || ![[NSScanner scannerWithString:digits] scanHexLongLong:&value]) return nil;
  if (digits.length == 6) value = (value << 8) | 0xFF;
  return [UIColor colorWithRed:((value >> 24) & 0xFF) / 255.0 green:((value >> 16) & 0xFF) / 255.0 blue:((value >> 8) & 0xFF) / 255.0 alpha:(value & 0xFF) / 255.0];
}

+ (UIImage *)image:(UIImage *)image overBackground:(NSDictionary *)background {
  NSString *mode = [background isKindOfClass:[NSDictionary class]] ? background[@"Mode"] : nil;
  if (![mode isKindOfClass:[NSString class]] || image.size.width <= 0 || image.size.height <= 0) return image;
  UIColor *color = LMStoreColorFromHex(background[@"Color"]), *color2 = LMStoreColorFromHex(background[@"Color2"]);
  UIImage *picture = nil;
  if ([mode isEqualToString:@"image"] && [background[@"Image"] isKindOfClass:[NSString class]] && ![background[@"Image"] containsString:@"/"]) {
    picture = [UIImage imageWithContentsOfFile:[LMBackgroundsDirectory stringByAppendingPathComponent:background[@"Image"]]];
  }
  BOOL usable = ([mode isEqualToString:@"color"] && color) || ([mode isEqualToString:@"gradient"] && color && color2) || picture;
  if (!usable) return image;

  CGSize size = image.size;
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
  format.scale = image.scale;
  return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    if ([mode isEqualToString:@"color"]) {
      [color setFill];
      UIRectFill(rect);
    } else if ([mode isEqualToString:@"gradient"]) {
      CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
      CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)@[(id)color.CGColor, (id)color2.CGColor], NULL);
      if (gradient) {
        // like on the home screen: 0 degrees from left to right, 90 from top to bottom, long enough to reach the corners
        double angle = [background[@"Angle"] doubleValue] * M_PI / 180.0, dx = cos(angle), dy = sin(angle);
        double half = (fabs(dx) * size.width + fabs(dy) * size.height) / 2;
        CGPoint center = CGPointMake(size.width / 2, size.height / 2);
        CGContextDrawLinearGradient(context.CGContext, gradient, CGPointMake(center.x - dx * half, center.y - dy * half), CGPointMake(center.x + dx * half, center.y + dy * half), kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(gradient);
      }
      CGColorSpaceRelease(space);
    } else {
      double factor = MAX(size.width / picture.size.width, size.height / picture.size.height);
      CGSize drawn = CGSizeMake(picture.size.width * factor, picture.size.height * factor);
      [picture drawInRect:CGRectMake((size.width - drawn.width) / 2, (size.height - drawn.height) / 2, drawn.width, drawn.height)];
    }
    [image drawInRect:rect];
  }];
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
