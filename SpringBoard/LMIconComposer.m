#import "LMIconComposer.h"
#import "../Shared/LMThemeLibrary.h"
#import <ImageIO/ImageIO.h>
#include <sys/stat.h>

// 128 pt @3x: big enough for the App Library and iPad home screen, theme artwork is capped at 512 px anyway
static const size_t LMComposedPixels = 384;

static CGImageRef LMCreateImage(NSString *path, size_t maxPixels) {
  if (!path.length) return NULL;
  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path isDirectory:NO], NULL);
  if (!source) return NULL;
  NSDictionary *options = @{
    (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
    (__bridge id)kCGImageSourceCreateThumbnailWithTransform : @YES,
    (__bridge id)kCGImageSourceThumbnailMaxPixelSize : @(maxPixels),
  };
  CGImageRef image = CGImageSourceGetCount(source) ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options) : NULL;
  CFRelease(source);
  return image;
}

static NSString *LMStamp(NSString *path) {
  struct stat info;
  if (!path || stat(path.fileSystemRepresentation, &info) != 0) return @"-";
  return [NSString stringWithFormat:@"%@@%lld.%ld/%lld", path, (long long)info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec, (long long)info.st_size];
}

// rounded rect with its own radius per corner, in CoreGraphics coordinates (y up)
static CGPathRef LMCreateCornerPath(CGFloat size, CGFloat topLeft, CGFloat topRight, CGFloat bottomRight, CGFloat bottomLeft) {
  CGMutablePathRef path = CGPathCreateMutable();
  CGPathMoveToPoint(path, NULL, topLeft, size);
  CGPathAddArcToPoint(path, NULL, size, size, size, size - topRight, topRight);
  CGPathAddArcToPoint(path, NULL, size, 0, size - bottomRight, 0, bottomRight);
  CGPathAddArcToPoint(path, NULL, 0, 0, 0, bottomLeft, bottomLeft);
  CGPathAddArcToPoint(path, NULL, 0, size, topLeft, size, topLeft);
  CGPathCloseSubpath(path);
  return path;
}

static CGPathRef LMCreateShapePath(NSString *shape, CGFloat size) {
  CGFloat round = size / 2;
  if ([shape isEqualToString:LMIconShapeCircle]) return LMCreateCornerPath(size, round, round, round, round);
  if ([shape isEqualToString:LMIconShapeRounded]) return LMCreateCornerPath(size, size * 0.14, size * 0.14, size * 0.14, size * 0.14);
  if ([shape isEqualToString:LMIconShapeTeardrop]) return LMCreateCornerPath(size, round, round, size * 0.12, round);
  return NULL;
}

// "#RRGGBB" or "#RRGGBBAA"
static BOOL LMParseColor(id hex, CGFloat rgba[4]) {
  if (![hex isKindOfClass:[NSString class]]) return NO;
  NSString *digits = [hex hasPrefix:@"#"] ? [hex substringFromIndex:1] : hex;
  unsigned long long value = 0;
  if ((digits.length != 6 && digits.length != 8) || ![[NSScanner scannerWithString:digits] scanHexLongLong:&value]) return NO;
  if (digits.length == 6) value = (value << 8) | 0xFF;
  rgba[0] = ((value >> 24) & 0xFF) / 255.0;
  rgba[1] = ((value >> 16) & 0xFF) / 255.0;
  rgba[2] = ((value >> 8) & 0xFF) / 255.0;
  rgba[3] = (value & 0xFF) / 255.0;
  return YES;
}

static CGContextRef LMCreateContext(size_t size);

// the artwork over the background, both stretched to size x size. NULL: nothing to draw.
static CGImageRef LMCreateArtworkOverBackground(CGImageRef artwork, NSDictionary *background, size_t size) {
  NSString *mode = [background isKindOfClass:[NSDictionary class]] ? background[@"Mode"] : nil;
  if (![mode isKindOfClass:[NSString class]]) return NULL;
  CGContextRef context = LMCreateContext(size);
  if (!context) return NULL;
  CGRect bounds = CGRectMake(0, 0, size, size);
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGFloat first[4], second[4];
  BOOL drawn = NO;
  if ([mode isEqualToString:@"color"] && LMParseColor(background[@"Color"], first)) {
    CGContextSetRGBFillColor(context, first[0], first[1], first[2], first[3]);
    CGContextFillRect(context, bounds);
    drawn = YES;
  } else if ([mode isEqualToString:@"gradient"] && LMParseColor(background[@"Color"], first) && LMParseColor(background[@"Color2"], second)) {
    CGFloat components[8] = { first[0], first[1], first[2], first[3], second[0], second[1], second[2], second[3] };
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
    if (gradient) {
      // 0 degrees from left to right, 90 from top to bottom, long enough to reach the corners (Core Graphics counts y upwards)
      double angle = [background[@"Angle"] doubleValue] * M_PI / 180.0, dx = cos(angle), dy = sin(angle);
      double half = (fabs(dx) + fabs(dy)) * size / 2, center = size / 2.0;
      CGContextDrawLinearGradient(context, gradient, CGPointMake(center - dx * half, center + dy * half), CGPointMake(center + dx * half, center - dy * half), kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
      CGGradientRelease(gradient);
      drawn = YES;
    }
  } else if ([mode isEqualToString:@"image"] && [background[@"Image"] isKindOfClass:[NSString class]]) {
    CGImageRef picture = LMCreateImage(LMRootPath(background[@"Image"]), size);
    if (picture && CGImageGetWidth(picture) && CGImageGetHeight(picture)) {
      double factor = MAX(size / (double)CGImageGetWidth(picture), size / (double)CGImageGetHeight(picture));
      double width = CGImageGetWidth(picture) * factor, height = CGImageGetHeight(picture) * factor;
      CGContextDrawImage(context, CGRectMake((size - width) / 2, (size - height) / 2, width, height), picture);
      drawn = YES;
    }
    CGImageRelease(picture);
  }
  CGImageRef result = NULL;
  if (drawn) {
    CGContextDrawImage(context, bounds, artwork);
    result = CGBitmapContextCreateImage(context);
  }
  CGContextRelease(context);
  CGColorSpaceRelease(space);
  return result;
}

static CGContextRef LMCreateContext(size_t size) {
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context = CGBitmapContextCreate(NULL, size, size, 8, 0, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  CGColorSpaceRelease(space);
  if (context) CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
  return context;
}

@implementation LMIconComposer {
  CGImageRef _mask;
  CGImageRef _underlay;
  CGImageRef _overlay;
  CGPathRef _shapePath;
}

- (instancetype)initWithShape:(NSString *)shape maskPath:(NSString *)maskPath effects:(NSDictionary<NSString *, NSString *> *)effects {
  if (!(self = [super init])) return nil;
  _pixelSize = LMComposedPixels;
  if ([shape isEqualToString:LMIconShapeThemeMask]) {
    _mask = LMCreateImage(maskPath, _pixelSize);
    if (!_mask) shape = LMIconShapeTheme;
  }
  _shape = [LMIconShapes() containsObject:shape] ? [shape copy] : LMIconShapeTheme;
  _shapePath = LMCreateShapePath(_shape, _pixelSize);
  _underlay = LMCreateImage(effects[LMEffectUnderlay], _pixelSize);
  _overlay = LMCreateImage(effects[LMEffectOverlay], _pixelSize);

  BOOL customShape = _mask || _shapePath || [_shape isEqualToString:LMIconShapeSquare];
  _drawsShape = customShape;
  _changesIcons = customShape || _underlay || _overlay;
  _signature = [NSString stringWithFormat:@"v1 %zu shape=%@ mask=%@ underlay=%@ overlay=%@", _pixelSize, _shape,
                _mask ? LMStamp(maskPath) : @"-", _underlay ? LMStamp(effects[LMEffectUnderlay]) : @"-", _overlay ? LMStamp(effects[LMEffectOverlay]) : @"-"];
  return self;
}

- (void)dealloc {
  CGImageRelease(_mask);
  CGImageRelease(_underlay);
  CGImageRelease(_overlay);
  CGPathRelease(_shapePath);
}

- (BOOL)writeIconWithArtwork:(CGImageRef)artwork effects:(BOOL)effects toPath:(NSString *)path {
  if (!artwork || !CGImageGetWidth(artwork) || !CGImageGetHeight(artwork)) return NO;
  CGRect bounds = CGRectMake(0, 0, _pixelSize, _pixelSize);

  // the artwork in its shape
  CGContextRef shaped = LMCreateContext(_pixelSize);
  if (!shaped) return NO;
  if (_shapePath) {
    CGContextAddPath(shaped, _shapePath);
    CGContextClip(shaped);
  }
  CGContextDrawImage(shaped, bounds, artwork);
  if (_mask) {
    // keeps the artwork where the mask is opaque
    CGContextSetBlendMode(shaped, kCGBlendModeDestinationIn);
    CGContextDrawImage(shaped, bounds, _mask);
  }
  CGImageRef shapedImage = CGBitmapContextCreateImage(shaped);
  CGContextRelease(shaped);
  if (!shapedImage) return NO;

  // underlay, artwork, overlay
  CGContextRef context = LMCreateContext(_pixelSize);
  if (!context) {
    CGImageRelease(shapedImage);
    return NO;
  }
  if (effects && _underlay) CGContextDrawImage(context, bounds, _underlay);
  CGContextDrawImage(context, bounds, shapedImage);
  if (effects && _overlay) CGContextDrawImage(context, bounds, _overlay);
  CGImageRelease(shapedImage);
  CGImageRef icon = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  if (!icon) return NO;

  NSString *temporary = [path stringByAppendingString:@".tmp"];
  CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:temporary isDirectory:NO], CFSTR("public.png"), 1, NULL);
  BOOL written = NO;
  if (destination) {
    CGImageDestinationAddImage(destination, icon, NULL);
    written = CGImageDestinationFinalize(destination);
    CFRelease(destination);
  }
  CGImageRelease(icon);
  if (written) written = rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) == 0;
  if (!written) {
    unlink(temporary.fileSystemRepresentation);
    return NO;
  }
  chmod(path.fileSystemRepresentation, 0644);
  return YES;
}

- (BOOL)writeIconWithArtworkAtPath:(NSString *)artworkPath effects:(BOOL)effects toPath:(NSString *)path {
  return [self writeIconWithArtworkAtPath:artworkPath effects:effects background:nil toPath:path];
}

- (BOOL)writeIconWithArtwork:(CGImageRef)artwork effects:(BOOL)effects background:(NSDictionary *)background toPath:(NSString *)path {
  // the background goes under the artwork, so the shape cuts both
  CGImageRef over = (_drawsShape && background && artwork) ? LMCreateArtworkOverBackground(artwork, background, _pixelSize) : NULL;
  BOOL written = [self writeIconWithArtwork:over ? over : artwork effects:effects toPath:path];
  CGImageRelease(over);
  return written;
}

- (BOOL)writeIconWithArtworkAtPath:(NSString *)artworkPath effects:(BOOL)effects background:(NSDictionary *)background toPath:(NSString *)path {
  CGImageRef artwork = LMCreateImage(artworkPath, _pixelSize);
  BOOL written = [self writeIconWithArtwork:artwork effects:effects background:background toPath:path];
  CGImageRelease(artwork);
  return written;
}

@end
