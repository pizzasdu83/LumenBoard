// Themed icons get their own digest (= icon cache key) in every process,
// iconservicesagent renders them from the theme png. When it doesn't (e.g. palera1n), the requesting process renders them itself.

#import "LMIconStore.h"
#import "LMStatus.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <stdatomic.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>

@interface ISConcreteIcon : NSObject
- (NSUUID *)digest;
@end

@interface ISBundleIdentifierIcon : ISConcreteIcon
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier;
- (NSString *)bundleIdentifier;
@end

@interface ISBundleIcon : ISConcreteIcon
- (instancetype)initWithBundleURL:(NSURL *)url type:(NSString *)type tag:(NSString *)tag tagClass:(NSString *)tagClass;
- (NSURL *)url;
@end

@interface ISApplicationIdentityIcon : ISConcreteIcon
- (instancetype)initWithApplicationIdentity:(id)identity;
- (NSString *)identityString;
@end

@interface ISResourceProvider : NSObject
- (instancetype)initWithResource:(id)resource templateResource:(id)templateResource;
- (void)setResourceType:(unsigned long long)resourceType;
- (void)setAllowNonDefaultAppearances:(BOOL)allow;
- (void)setAllowAlterationsToResourceArt:(BOOL)allow;
- (void)setIconResource:(id)resource;
- (void)setSuggestedRecipe:(id)recipe;
@end

@interface IFImage : NSObject
- (double)scale;
- (instancetype)initWithCGImage:(CGImageRef)image scale:(double)scale;
- (NSData *)validationToken;
- (CGImageRef)CGImage;
@end

@interface ISImageDescriptor : NSObject
- (instancetype)initWithSize:(CGSize)size scale:(double)scale;
- (void)setShouldApplyMask:(BOOL)shouldApplyMask;
@end

@interface ISGenerationRequest : NSObject
- (void)setIcon:(id)icon;
- (void)setImageDescriptor:(id)descriptor;
- (IFImage *)generateImage;
@end

@interface IFImageBag : NSObject
- (instancetype)initWithImages:(NSArray *)images;
@end

@interface LSApplicationRecord : NSObject
- (instancetype)initWithURL:(NSURL *)url allowPlaceholder:(BOOL)allowPlaceholder error:(NSError **)error;
- (NSString *)bundleIdentifier;
@end

@interface LSApplicationIdentity : NSObject
- (instancetype)initWithIdentityString:(NSString *)identityString;
- (NSString *)bundleIdentifier;
@end

static BOOL LMHooksInstalled;
static Ivar LMDigestIvar;
static Class LMProviderClass;
static Class LMRecipeClass;
static NSCache *LMImageBags;
static NSCache *LMAppURLIdentifiers;
static char LMIconEntryKey;
static char LMThemedIconKey;
// cleared once iconservicesagent hands back a theme icon without the theme, reset when the map changes
static atomic_bool LMAgentRendersThemes = true;
// LMCoreCopyStockIconImage is rendering on this thread: no themed digests, no theme providers
static __thread BOOL LMRenderingStock;

#pragma mark - Digests

static NSUUID *LMThemedDigest(NSUUID *stockDigest, NSString *token) {
  uuid_t bytes;
  [stockDigest getUUIDBytes:bytes];
  NSData *tokenData = [token dataUsingEncoding:NSUTF8StringEncoding];
  CC_SHA256_CTX context;
  CC_SHA256_Init(&context);
  CC_SHA256_Update(&context, "lumenboard-theme-icon", 21);
  CC_SHA256_Update(&context, bytes, sizeof(bytes));
  CC_SHA256_Update(&context, tokenData.bytes, (CC_LONG)tokenData.length);
  unsigned char hash[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256_Final(hash, &context);
  // shaped like a name-based (v5) UUID
  hash[6] = (hash[6] & 0x0F) | 0x50;
  hash[8] = (hash[8] & 0x3F) | 0x80;
  return [[NSUUID alloc] initWithUUIDBytes:hash];
}

static void LMMarkThemed(ISConcreteIcon *icon, NSString *bundleIdentifier) {
  if (!icon || LMRenderingStock) return;
  NSDictionary *entry = [[LMIconStore sharedStore] iconForBundleIdentifier:bundleIdentifier];
  if (!entry) return;
  id stockDigest = object_getIvar(icon, LMDigestIvar);
  if (![stockDigest isKindOfClass:[NSUUID class]]) return;
  object_setIvarWithStrongDefault(icon, LMDigestIvar, LMThemedDigest(stockDigest, entry[LMIconToken]));
  objc_setAssociatedObject(icon, &LMThemedIconKey, bundleIdentifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
  LMStatusCount(LMCounterThemedIcons);
}

// bundle identifier if this process gave the icon a themed digest
static NSString *LMThemedIconIdentifier(id icon) {
  return objc_getAssociatedObject(icon, &LMThemedIconKey);
}

static NSString *LMBundleIdentifierForAppURL(NSURL *url) {
  if (!url.isFileURL || [url.pathExtension caseInsensitiveCompare:@"app"] != NSOrderedSame) return nil;
  NSString *cached = [LMAppURLIdentifiers objectForKey:url.path];
  if (cached) return cached.length ? cached : nil;
  NSString *bundleIdentifier = nil;
  Class recordClass = objc_getClass("LSApplicationRecord");
  if ([recordClass instancesRespondToSelector:@selector(initWithURL:allowPlaceholder:error:)])
    bundleIdentifier = [[[recordClass alloc] initWithURL:url allowPlaceholder:YES error:nil] bundleIdentifier];
  if (!bundleIdentifier) bundleIdentifier = [NSBundle bundleWithURL:url].bundleIdentifier;
  [LMAppURLIdentifiers setObject:(bundleIdentifier ? : @"") forKey:url.path];
  return bundleIdentifier;
}

static NSString *LMBundleIdentifierForIdentity(id identity) {
  return [identity respondsToSelector:@selector(bundleIdentifier)] ? [identity bundleIdentifier] : nil;
}

#pragma mark - Artwork

// largest icon drawn is 83.5 pt @2x / 60 pt @3x, leave room for big App Library and widget sizes
static const NSUInteger LMMaxArtworkPixels = 512;

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

// the image behind the icons, decoded once (the same one goes behind every icon). The caller releases it.
static CGImageRef LMBackgroundPicture(NSString *path) {
  static NSCache *pictures;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    pictures = [NSCache new];
    pictures.countLimit = 4;
  });
  if (![path isKindOfClass:[NSString class]] || !path.length) return NULL;
  id cached = [pictures objectForKey:path];
  if (cached) return CGImageRetain((__bridge CGImageRef)cached);
  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path isDirectory:NO], NULL);
  if (!source) return NULL;
  NSDictionary *options = @{
    (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
    (__bridge id)kCGImageSourceCreateThumbnailWithTransform : @YES,
    (__bridge id)kCGImageSourceThumbnailMaxPixelSize : @(LMMaxArtworkPixels),
  };
  CGImageRef picture = CGImageSourceGetCount(source) ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options) : NULL;
  CFRelease(source);
  if (!picture) return NULL;
  [pictures setObject:(__bridge id)picture forKey:path cost:CGImageGetBytesPerRow(picture) * CGImageGetHeight(picture)];
  return picture;
}

// the icon drawn over a color, a gradient or a picture. Returns a new image, NULL if there is nothing to draw.
static CGImageRef LMCreateImageOverBackground(CGImageRef icon, NSDictionary *background) {
  size_t width = CGImageGetWidth(icon), height = CGImageGetHeight(icon);
  if (!width || !height || ![background isKindOfClass:[NSDictionary class]]) return NULL;
  NSString *mode = background[@"Mode"];
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  if (!context) {
    CGColorSpaceRelease(space);
    return NULL;
  }
  CGRect rect = CGRectMake(0, 0, width, height);
  CGFloat first[4], second[4];
  BOOL drawn = NO;
  if ([mode isEqualToString:@"color"] && LMParseColor(background[@"Color"], first)) {
    CGContextSetRGBFillColor(context, first[0], first[1], first[2], first[3]);
    CGContextFillRect(context, rect);
    drawn = YES;
  } else if ([mode isEqualToString:@"gradient"] && LMParseColor(background[@"Color"], first) && LMParseColor(background[@"Color2"], second)) {
    CGFloat components[8] = { first[0], first[1], first[2], first[3], second[0], second[1], second[2], second[3] };
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
    if (gradient) {
      // 0 degrees goes from left to right, 90 from top to bottom (like on screen), long enough to reach the corners
      double angle = [background[@"Angle"] doubleValue] * M_PI / 180.0, dx = cos(angle), dy = sin(angle);
      double half = (fabs(dx) * width + fabs(dy) * height) / 2;
      CGPoint center = CGPointMake(width / 2.0, height / 2.0);
      // Core Graphics counts y upwards
      CGPoint start = CGPointMake(center.x - dx * half, center.y + dy * half), end = CGPointMake(center.x + dx * half, center.y - dy * half);
      CGContextDrawLinearGradient(context, gradient, start, end, kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
      CGGradientRelease(gradient);
      drawn = YES;
    }
  } else if ([mode isEqualToString:@"image"]) {
    CGImageRef picture = LMBackgroundPicture(background[@"Image"]);
    if (picture && CGImageGetWidth(picture) && CGImageGetHeight(picture)) {
      double factor = MAX(width / (double)CGImageGetWidth(picture), height / (double)CGImageGetHeight(picture));
      double drawnWidth = CGImageGetWidth(picture) * factor, drawnHeight = CGImageGetHeight(picture) * factor;
      CGContextDrawImage(context, CGRectMake((width - drawnWidth) / 2, (height - drawnHeight) / 2, drawnWidth, drawnHeight), picture);
      drawn = YES;
    }
    CGImageRelease(picture);
  }
  CGImageRef result = NULL;
  if (drawn) {
    CGContextDrawImage(context, rect, icon);
    result = CGBitmapContextCreateImage(context);
  }
  CGContextRelease(context);
  CGColorSpaceRelease(space);
  return result;
}

// a tinted-looking version of an icon: grayscale (iOS puts the tint color on it), over black where iOS masks the icon
// itself. Returns a new image, NULL if it can't be drawn.
static CGImageRef LMCreateTintableImage(CGImageRef icon, BOOL overBlack) {
  size_t width = CGImageGetWidth(icon), height = CGImageGetHeight(icon);
  if (!width || !height) return NULL;
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  CGColorSpaceRelease(space);
  if (!context) return NULL;
  CGRect rect = CGRectMake(0, 0, width, height);
  if (overBlack) {
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, rect);
  }
  CGContextDrawImage(context, rect, icon);
  uint8_t *data = CGBitmapContextGetData(context);
  size_t stride = CGBitmapContextGetBytesPerRow(context);
  if (data) {
    for (size_t y = 0; y < height; y++) {
      uint8_t *row = data + y * stride;
      for (size_t x = 0; x < width; x++) {
        uint8_t *pixel = row + x * 4; // B, G, R, A (premultiplied)
        uint8_t gray = (uint8_t)((pixel[2] * 77 + pixel[1] * 151 + pixel[0] * 28) >> 8);
        if (gray > pixel[3]) gray = pixel[3];
        pixel[0] = pixel[1] = pixel[2] = gray;
      }
    }
  }
  CGImageRef result = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  return result;
}

// background: goes behind the icon (nil: the icon as it is)
// tintable: 0 = as it is, 1 = grayscale for tinted mode, 2 = grayscale over black (for icons iOS masks itself)
static id LMImageBag(NSString *path, NSDictionary *background, int tintable) {
  if (!path.length) return nil;
  NSString *key = background ? [NSString stringWithFormat:@"%@\n%@", path, LMBackgroundSignature(background)] : path;
  if (tintable) key = [key stringByAppendingFormat:@"\ntint%d", tintable];
  id bag = [LMImageBags objectForKey:key];
  if (bag) return bag;

  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path isDirectory:NO], NULL);
  if (!source) return nil;
  NSDictionary *properties = CGImageSourceGetCount(source) ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
  double sourceWidth = [properties[(__bridge id)kCGImagePropertyPixelWidth] doubleValue];
  // themes often ship 1024 px icons, no icon is drawn that big and SpringBoard / iconservicesagent have little memory to spare
  NSDictionary *options = @{
    (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
    (__bridge id)kCGImageSourceCreateThumbnailWithTransform : @YES,
    (__bridge id)kCGImageSourceThumbnailMaxPixelSize : @(LMMaxArtworkPixels),
  };
  CGImageRef image = sourceWidth ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options) : NULL;
  CFRelease(source);
  if (!image) return nil;
  if (background) {
    CGImageRef composed = LMCreateImageOverBackground(image, background);
    if (composed) {
      CGImageRelease(image);
      image = composed;
    }
  }

  if (tintable) {
    CGImageRef gray = LMCreateTintableImage(image, tintable == 2);
    if (gray) {
      CGImageRelease(image);
      image = gray;
    }
  }

  NSString *name = path.lastPathComponent.lowercaseString;
  double scale = [name containsString:@"@3x"] ? 3.0 : ([name containsString:@"@2x"] ? 2.0 : 1.0);
  NSUInteger cost = CGImageGetBytesPerRow(image) * CGImageGetHeight(image);
  IFImage *artwork = (CGImageGetWidth(image) && CGImageGetHeight(image)) ? [[objc_getClass("IFImage") alloc] initWithCGImage:image scale:scale] : nil;
  CGImageRelease(image);
  if (!artwork) return nil;

  bag = [[objc_getClass("IFImageBag") alloc] initWithImages:@[artwork]];
  if (bag) [LMImageBags setObject:bag forKey:key cost:cost];
  return bag;
}

// YES: iOS masks this icon with its icon shape. Icons with a custom shape have it drawn in already. Maps before 1.1.0 have one setting for all icons.
static BOOL LMEntryIsMasked(NSDictionary *entry) {
  NSNumber *systemShape = [entry[LMIconSystemShape] isKindOfClass:[NSNumber class]] ? entry[LMIconSystemShape] : nil;
  return systemShape ? systemShape.boolValue : [LMIconStore sharedStore].usesSystemIconShape;
}

// the background only goes behind icons with the iOS shape (otherwise the corners would be square), not behind the app's own icon
static NSDictionary *LMBackgroundForEntry(NSDictionary *entry, long long appearance) {
  if (!LMEntryIsMasked(entry) || [entry[LMIconStock] boolValue]) return nil;
  return [[LMIconStore sharedStore] backgroundForAppearance:appearance];
}

// what iOS asks for: dark or not, and the style (0 normal, 1 tinted, 2 clear). iOS 26 names: Light, Dark, ClearLight, ClearDark, TintedLight, TintedDark.
// The numbers behind them are not documented, so the words in the descriptor count too. The report shows what was asked and what was chosen.
static void LMClassifyRequest(id descriptor, long long appearance, long long variant, BOOL *dark, int *style) {
  // seen on iOS 26.0: variant 0 = normal (appearance 0 light / 1 dark), 2 = tinted (the descriptor carries the tint color), 3 = clear
  int kind = 0;
  if (variant == 3) kind = 2;
  else if (variant != 0) kind = 1;
  else if (appearance == 2) kind = 1;
  *style = kind;
  *dark = (appearance == 1);
}

// the theme's png for this request: dark, or tinted / clear (light or dark). nil if the theme has none.
static NSString *LMVariantForRequest(NSDictionary *entry, BOOL dark, int style, NSString **slotOut) {
  NSArray *chain;
  if (style == 1) chain = dark ? @[LMIconTintedDark, LMIconTinted, LMIconTintedLight] : @[LMIconTintedLight, LMIconTinted, LMIconTintedDark];
  else if (style == 2) chain = dark ? @[LMIconClearDark, LMIconClearLight, LMIconTinted] : @[LMIconClearLight, LMIconClearDark, LMIconTinted];
  else chain = dark ? @[LMIconDark] : @[];
  for (NSString *slot in chain) {
    if ([entry[slot] isKindOfClass:[NSString class]]) {
      if (slotOut) *slotOut = slot;
      return entry[slot];
    }
  }
  return nil;
}

// written to the report once per kind of request
static void LMLogDescriptor(id descriptor, long long appearance, long long variant, BOOL dark, int style, NSString *chosen) {
  static NSMutableSet *seen;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ seen = [NSMutableSet new]; });
  NSString *key = [NSString stringWithFormat:@"%lld/%lld/%d/%d/%@", appearance, variant, dark, style, chosen ? : @"-"];
  BOOL isNew = NO;
  @synchronized (seen) {
    if (![seen containsObject:key] && seen.count < 60) {
      [seen addObject:key];
      isNew = YES;
    }
  }
  if (!isNew) return;
  NSString *text = [[descriptor description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
  if (text.length > 220) text = [text substringToIndex:220];
  LMStatusEvent(@"asked appearance=%lld variant=%lld (dark=%d style=%d) -> %@: %@", appearance, variant, dark, style, chosen ? : @"fallback", text);
}

// LMThemeIconProvider: use the theme's -dark / -tinted / -clear... png if there is one
static void LMProviderConfigure(ISResourceProvider *self, SEL _cmd, id descriptor) {
  NSDictionary *entry = objc_getAssociatedObject(self, &LMIconEntryKey);
  long long appearance = [descriptor respondsToSelector:@selector(appearance)] ? ((long long (*)(id, SEL))objc_msgSend)(descriptor, @selector(appearance)) : 0;
  long long appearanceVariant = [descriptor respondsToSelector:@selector(appearanceVariant)] ? ((long long (*)(id, SEL))objc_msgSend)(descriptor, @selector(appearanceVariant)) : 0;
  BOOL dark = NO;
  int style = 0;
  LMClassifyRequest(descriptor, appearance, appearanceVariant, &dark, &style);
  NSString *chosenSlot = nil;
  NSString *variant = LMVariantForRequest(entry, dark, style, &chosenSlot);
  // light and dark mode have their own background, tinted and clear icons have none
  NSDictionary *background = style ? nil : LMBackgroundForEntry(entry, appearance);
  // no dark icon, but a dark background: the normal icon goes over it
  if (!variant && !style && dark && background) {
    variant = entry[LMIconLight];
    chosenSlot = @"Light+background";
  }
  // tinted or clear mode and the theme has no icon for it: iOS can't derive one from the normal icon and the icon would be blank.
  // Make one from the dark (or normal) icon instead, in grayscale like a real tinted icon.
  int tintable = 0;
  if (!variant && style && ![LMIconStore sharedStore].keepsIconsInDarkAndTinted) {
    variant = entry[LMIconDark] ? : entry[LMIconLight];
    tintable = LMEntryIsMasked(entry) ? 2 : 1;
    chosenSlot = @"grayscale";
  }
  LMLogDescriptor(descriptor, appearance, appearanceVariant, dark, style, chosenSlot);
  id bag = LMImageBag(variant, background, tintable);
  if (bag) {
    [self setIconResource:bag];
    // the theme drew dark itself, don't let iOS derive it again. Tinted and clear: iOS puts the tint color / the glass on the theme's gray icon
    if ([self respondsToSelector:@selector(setAllowAlterationsToResourceArt:)]) [self setAllowAlterationsToResourceArt:style ? YES : NO];
  }
  struct objc_super superclass = { self, class_getSuperclass(LMProviderClass) };
  ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&superclass, _cmd, descriptor);
}

#pragma mark - Tinted and clear icons, drawn here

static BOOL LMRenderedWithTheme(IFImage *image);

// IconServices throws away an IFImage that has no validation token. Everything IconServices draws carries one, an image made here needs it too.
static BOOL LMGiveValidationToken(IFImage *image) {
  static NSData *token;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    SEL validToken = NSSelectorFromString(@"_is_validToken");
    if ([NSData respondsToSelector:validToken]) token = ((NSData *(*)(Class, SEL))objc_msgSend)([NSData class], validToken);
  });
  if (!token.length || !image) return NO;
  SEL setter = NSSelectorFromString(@"setValidationToken:");
  if ([image respondsToSelector:setter]) {
    ((void (*)(id, SEL, id))objc_msgSend)(image, setter, token);
  } else {
    Ivar ivar = class_getInstanceVariable([image class], "_validationToken");
    if (ivar) object_setIvarWithStrongDefault(image, ivar, token);
  }
  return LMRenderedWithTheme(image);
}



// iOS 26 tinted and clear icons: what IconServices draws is what the home screen shows, and for themed icons it came out empty.
// So the finished icon is drawn here: the theme's png at the size asked for, with the iOS shape if the request wants it.
static NSCache *LMOwnImages;

static NSString *LMOwnFileStamp(NSString *path) {
  struct stat info;
  if (stat(path.fileSystemRepresentation, &info) != 0) return @"0";
  return [NSString stringWithFormat:@"%ld.%ld", (long)info.st_mtimespec.tv_sec, (long)info.st_size];
}

static BOOL LMTintFromDescriptor(id descriptor, CGFloat rgb[3]) {
  static NSRegularExpression *expression;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ expression = [NSRegularExpression regularExpressionWithPattern:@"\\bt:([0-9.]+):([0-9.]+):([0-9.]+):([0-9.]+)" options:0 error:nil]; });
  NSString *text = [descriptor description];
  NSTextCheckingResult *match = text.length ? [expression firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] : nil;
  if (!match || match.numberOfRanges < 5) return NO;
  for (int i = 0; i < 3; i++) rgb[i] = [[text substringWithRange:[match rangeAtIndex:i + 1]] doubleValue];
  return [[text substringWithRange:[match rangeAtIndex:4]] doubleValue] > 0.01;
}

static CGImageRef LMCreateArtwork(NSString *path) {
  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path isDirectory:NO], NULL);
  if (!source) return NULL;
  NSDictionary *options = @{
    (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
    (__bridge id)kCGImageSourceCreateThumbnailWithTransform : @YES,
    (__bridge id)kCGImageSourceThumbnailMaxPixelSize : @(LMMaxArtworkPixels),
  };
  CGImageRef image = CGImageSourceGetCount(source) ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options) : NULL;
  CFRelease(source);
  return image;
}

static IFImage *LMOwnTintedImage(ISConcreteIcon *icon, id descriptor);

// TEST BUILD: tinted and clear are handled differently per app, to find out why themed icons stay empty
// tinted and clear: the image comes from iconservicesagent (iOS accepts that), our picture is put inside it
static BOOL LMTestStock(ISConcreteIcon *icon, id descriptor) {
  if (!LMThemedIconIdentifier(icon) || LMRenderingStock || !descriptor) return NO;
  long long variant = [descriptor respondsToSelector:@selector(appearanceVariant)] ? ((long long (*)(id, SEL))objc_msgSend)(descriptor, @selector(appearanceVariant)) : 0;
  return variant == 2 || variant == 3;
}

// nil: not a tinted or clear request for a themed icon, iOS does it
static IFImage *LMOwnTintedImage(ISConcreteIcon *icon, id descriptor) {
  NSString *bundleIdentifier = LMThemedIconIdentifier(icon);
  if (!bundleIdentifier || LMRenderingStock || !descriptor) return nil;
  BOOL testSolid = [bundleIdentifier isEqualToString:@"com.apple.calculator"]; // TEST: magenta
  long long appearance = [descriptor respondsToSelector:@selector(appearance)] ? ((long long (*)(id, SEL))objc_msgSend)(descriptor, @selector(appearance)) : 0;
  long long variant = [descriptor respondsToSelector:@selector(appearanceVariant)] ? ((long long (*)(id, SEL))objc_msgSend)(descriptor, @selector(appearanceVariant)) : 0;
  BOOL dark = NO;
  int style = 0;
  LMClassifyRequest(descriptor, appearance, variant, &dark, &style);
  if (!style) return nil;
  NSDictionary *entry = [[LMIconStore sharedStore] iconForBundleIdentifier:bundleIdentifier];
  if (!entry) return nil;

  NSString *slot = nil;
  NSString *path = LMVariantForRequest(entry, dark, style, &slot);
  // the theme's own TintedLight/Dark and ClearLight/Dark are finished icons. A gray one (-tinted, or made from the dark/normal icon) gets the tint color here.
  BOOL colorize = NO, overBlack = NO;
  if (!path) {
    if ([LMIconStore sharedStore].keepsIconsInDarkAndTinted) return nil;
    path = entry[LMIconDark] ? : entry[LMIconLight];
    slot = @"grayscale";
    colorize = YES;
    overBlack = YES;
  } else if ([slot isEqualToString:LMIconTinted]) {
    colorize = YES;
  }
  if (![path isKindOfClass:[NSString class]]) return nil;

  CGSize size = [descriptor respondsToSelector:@selector(size)] ? ((CGSize (*)(id, SEL))objc_msgSend)(descriptor, @selector(size)) : CGSizeZero;
  double scale = [descriptor respondsToSelector:@selector(scale)] ? ((double (*)(id, SEL))objc_msgSend)(descriptor, @selector(scale)) : 0;
  if (scale <= 0) scale = 2;
  size_t width = (size_t)ceil(size.width * scale), height = (size_t)ceil(size.height * scale);
  if (!width || !height || width > 2048 || height > 2048) return nil;
  BOOL masked = [descriptor respondsToSelector:@selector(shouldApplyMask)] ? ((BOOL (*)(id, SEL))objc_msgSend)(descriptor, @selector(shouldApplyMask)) : NO;
  CGFloat tint[3] = { 0, 0, 0 };
  BOOL hasTint = style == 1 && colorize && LMTintFromDescriptor(descriptor, tint);

  static dispatch_once_t once;
  dispatch_once(&once, ^{
    LMOwnImages = [NSCache new];
    LMOwnImages.countLimit = 200;
  });
  NSString *key = [NSString stringWithFormat:@"%d|%@|%zux%zu|%@|%d%d%d%d|%d|%.3f,%.3f,%.3f", testSolid, path, width, height, LMOwnFileStamp(path), masked, colorize, overBlack, dark, style, tint[0], tint[1], tint[2]];
  IFImage *cached = [LMOwnImages objectForKey:key];
  if (cached) return cached;

  CGImageRef artwork = LMCreateArtwork(path);
  if (!artwork) return nil;
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  CGColorSpaceRelease(space);
  if (!context) {
    CGImageRelease(artwork);
    return nil;
  }
  CGRect rect = CGRectMake(0, 0, width, height);
  if (masked) {
    CGFloat radius = MIN(width, height) * 0.2237;
    CGPathRef shape = CGPathCreateWithRoundedRect(rect, radius, radius, NULL);
    CGContextAddPath(context, shape);
    CGContextClip(context);
    CGPathRelease(shape);
  }
  if (overBlack) {
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, rect);
  }
  CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
  double factor = MAX(width / (double)CGImageGetWidth(artwork), height / (double)CGImageGetHeight(artwork));
  double drawnWidth = CGImageGetWidth(artwork) * factor, drawnHeight = CGImageGetHeight(artwork) * factor;
  if (testSolid) {
    CGContextSetRGBFillColor(context, 1, 0, 1, 1);
    CGContextFillRect(context, rect);
  } else {
    CGContextDrawImage(context, CGRectMake((width - drawnWidth) / 2, (height - drawnHeight) / 2, drawnWidth, drawnHeight), artwork);
  }
  CGImageRelease(artwork);

  if (!testSolid && (colorize || style == 2)) {
    uint8_t *data = CGBitmapContextGetData(context);
    size_t stride = CGBitmapContextGetBytesPerRow(context);
    // tinted dark: the tint on black. Tinted light: the tint, lightened. Clear: just gray.
    CGFloat multiplier[3] = { 1, 1, 1 };
    if (hasTint) for (int i = 0; i < 3; i++) multiplier[i] = dark ? tint[i] : 0.5 * tint[i] + 0.5;
    if (data && colorize) {
      for (size_t y = 0; y < height; y++) {
        uint8_t *row = data + y * stride;
        for (size_t x = 0; x < width; x++) {
          uint8_t *pixel = row + x * 4; // B, G, R, A (premultiplied)
          double gray = (pixel[2] * 77 + pixel[1] * 151 + pixel[0] * 28) / 256.0;
          if (gray > pixel[3]) gray = pixel[3];
          pixel[0] = (uint8_t)(gray * multiplier[2]);
          pixel[1] = (uint8_t)(gray * multiplier[1]);
          pixel[2] = (uint8_t)(gray * multiplier[0]);
        }
      }
    }
  }
  CGImageRef result = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  if (!result) return nil;
  IFImage *image = [[objc_getClass("IFImage") alloc] initWithCGImage:result scale:scale];
  CGImageRelease(result);
  if (!image) return nil;
  LMGiveValidationToken(image);
  [LMOwnImages setObject:image forKey:key cost:width * height * 4];
  LMLogDescriptor(descriptor, appearance, variant, dark, style, [@"own: " stringByAppendingString:slot ? : @"?"]);
  return image;
}

// TEST: what an IFImage from iconservicesagent looks like, and putting our picture inside one
static void LMLogImage(NSString *label, IFImage *image) {
  CGImageRef cg = [image respondsToSelector:@selector(CGImage)] ? [image CGImage] : NULL;
  NSData *token = [image respondsToSelector:@selector(validationToken)] ? [image validationToken] : nil;
  CGColorSpaceRef space = cg ? CGImageGetColorSpace(cg) : NULL;
  NSString *spaceName = space ? CFBridgingRelease(CGColorSpaceCopyName(space)) : nil;
  double scale = [image respondsToSelector:@selector(scale)] ? ((double (*)(id, SEL))objc_msgSend)(image, @selector(scale)) : 0;
  NSMutableString *extra = [NSMutableString new];
  for (NSString *name in @[@"_data", @"_layerData", @"_ICRIconLayer", @"_finalizedIcon", @"_CALayer", @"_catalog"]) {
    Ivar ivar = class_getInstanceVariable([image class], name.UTF8String);
    id value = ivar ? object_getIvar(image, ivar) : nil;
    [extra appendFormat:@" %@=%@", [name substringFromIndex:1], !ivar ? @"n/a" : (!value ? @"nil" : ([value isKindOfClass:[NSData class]] ? [NSString stringWithFormat:@"%lub", (unsigned long)[(NSData *)value length]] : @"set"))];
  }
  LMStatusEvent(@"%@: %@ cg=%zux%zu bpc=%zu info=0x%x space=%@ scale=%.1f token=%lu%@", label, NSStringFromClass([image class]), cg ? CGImageGetWidth(cg) : 0, cg ? CGImageGetHeight(cg) : 0, cg ? CGImageGetBitsPerComponent(cg) : 0, cg ? (unsigned)CGImageGetBitmapInfo(cg) : 0, spaceName ? : @"-", scale, (unsigned long)token.length, extra);
}

static BOOL LMSwapCGImage(IFImage *image, CGImageRef replacement) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSMutableArray *names = [NSMutableArray new];
    for (Class c = [image class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
      unsigned count = 0;
      Ivar *list = class_copyIvarList(c, &count);
      for (unsigned i = 0; i < count; i++) [names addObject:[NSString stringWithFormat:@"%s(%s)", ivar_getName(list[i]), ivar_getTypeEncoding(list[i]) ? : "?"]];
      free(list);
    }
    LMStatusEvent(@"IFImage ivars: %@", [names componentsJoinedByString:@" "]);
  });
  for (Class c = [image class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
    unsigned count = 0;
    Ivar *list = class_copyIvarList(c, &count);
    for (unsigned i = 0; i < count; i++) {
      const char *type = ivar_getTypeEncoding(list[i]);
      if (type && strncmp(type, "^{CGImage", 9) == 0) {
        CGImageRef *slot = (CGImageRef *)((uint8_t *)(__bridge void *)image + ivar_getOffset(list[i]));
        *slot = CGImageRetain(replacement); // the old picture is left alone on purpose
        free(list);
        return YES;
      }
    }
    free(list);
  }
  return NO;
}

static IFImage *LMTestSwap(ISConcreteIcon *icon, id descriptor, IFImage *stock) {
  IFImage *own = LMOwnTintedImage(icon, descriptor);
  static NSMutableSet *traced;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ traced = [NSMutableSet new]; });
  long long variant = [descriptor respondsToSelector:@selector(appearanceVariant)] ? ((long long (*)(id, SEL))objc_msgSend)(descriptor, @selector(appearanceVariant)) : 0;
  long long appearance = [descriptor respondsToSelector:@selector(appearance)] ? ((long long (*)(id, SEL))objc_msgSend)(descriptor, @selector(appearance)) : 0;
  NSString *traceKey = [NSString stringWithFormat:@"%@/%lld/%lld", LMThemedIconIdentifier(icon), appearance, variant];
  BOOL trace = NO;
  @synchronized (traced) {
    if (![traced containsObject:traceKey] && traced.count < 14) {
      [traced addObject:traceKey];
      trace = YES;
    }
  }
  CGImageRef cg = [own respondsToSelector:@selector(CGImage)] ? [own CGImage] : NULL;
  BOOL swapped = NO;
  if (stock && cg) swapped = LMSwapCGImage(stock, cg);
  if (trace) LMStatusEvent(@"deliver %@: agent image %@, ours %@, swapped %@", traceKey, stock ? @"yes" : @"no", cg ? @"yes" : @"no", swapped ? @"yes" : @"no");
  if (!stock) return own;
  return stock;
}

// LMThemeIconRecipe: app icon recipe without the mask
static BOOL LMRecipeShouldApplyMask(id self, SEL _cmd) {
  return NO;
}

// and without the white/black plate behind the icon
static id LMRecipePrimaryEffect(id self, SEL _cmd, id __autoreleasing *backgroundContent) {
  struct objc_super superclass = { self, class_getSuperclass(LMRecipeClass) };
  id effect = ((id (*)(struct objc_super *, SEL, id __autoreleasing *))objc_msgSendSuper)(&superclass, _cmd, backgroundContent);
  if (backgroundContent) *backgroundContent = nil;
  return effect;
}

static ISResourceProvider *LMMakeProvider(NSDictionary *entry) {
  LMIconStore *store = [LMIconStore sharedStore];
  id bag = LMImageBag(entry[LMIconLight], LMBackgroundForEntry(entry, 0), 0);
  if (!bag) {
    LMStatusCount(LMCounterUnreadableImages);
    if (LMStatusCounterValue(LMCounterUnreadableImages) <= 5) LMStatusEvent(@"can't load %@", entry[LMIconLight]);
  }
  if (!bag || !LMProviderClass) return nil;
  ISResourceProvider *provider = [[LMProviderClass alloc] initWithResource:bag templateResource:nil];
  if (!provider) return nil;
  objc_setAssociatedObject(provider, &LMIconEntryKey, entry, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  // 1 = app icon
  if ([provider respondsToSelector:@selector(setResourceType:)]) [provider setResourceType:1];
  if ([provider respondsToSelector:@selector(setAllowNonDefaultAppearances:)]) [provider setAllowNonDefaultAppearances:!store.keepsIconsInDarkAndTinted];
  if ([provider respondsToSelector:@selector(setAllowAlterationsToResourceArt:)]) [provider setAllowAlterationsToResourceArt:YES];
  BOOL masked = LMEntryIsMasked(entry);
  // only used if the descriptor doesn't ask for a shape itself
  if (!masked && LMRecipeClass && [provider respondsToSelector:@selector(setSuggestedRecipe:)]) [provider setSuggestedRecipe:[LMRecipeClass new]];
  LMStatusCount(LMCounterProvidersMade);
  return provider;
}

// only for requests with the themed digest, a process without the tweak wants the stock icon
static ISResourceProvider *LMProviderForRequest(ISConcreteIcon *request, NSString *bundleIdentifier, ISConcreteIcon *(^themedTwin)(void)) {
  if (!bundleIdentifier || LMRenderingStock) return nil;
  // the requesting process may already use a newer map
  [[LMIconStore sharedStore] reloadIfMapChanged];
  NSDictionary *entry = [[LMIconStore sharedStore] iconForBundleIdentifier:bundleIdentifier];
  if (!entry) return nil;
  NSUUID *expected = [themedTwin() digest];
  if (!expected || ![expected isEqual:[request digest]]) {
    LMStatusCount(LMCounterDigestMismatches);
    if (LMStatusCounterValue(LMCounterDigestMismatches) <= 5) LMStatusEvent(@"stock request for themed app %@", bundleIdentifier);
    return nil;
  }
  return LMMakeProvider(entry);
}

#pragma mark - Rendering in this process

// The theme provider has no LaunchServices resource token, so everything it renders carries IconServices'
// "always valid" token. A theme icon with any other token was rendered by an iconservicesagent without LumenBoard.
static BOOL LMRenderedWithTheme(IFImage *image) {
  static NSData *themeToken;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    SEL validToken = NSSelectorFromString(@"_is_validToken");
    if ([NSData respondsToSelector:validToken]) themeToken = ((NSData *(*)(Class, SEL))objc_msgSend)([NSData class], validToken);
  });
  // can't tell, trust the agent
  if (!themeToken.length) return image != nil;
  NSData *token = [image respondsToSelector:@selector(validationToken)] ? [image validationToken] : nil;
  // the persistent cache keeps 40 bytes of it
  NSUInteger length = MIN(themeToken.length, (NSUInteger)40);
  return [token isKindOfClass:[NSData class]] && token.length >= length && !memcmp(token.bytes, themeToken.bytes, length);
}

static void LMAgentMissedTheme(id icon) {
  LMStatusCount(LMCounterAgentStock);
  if (atomic_exchange(&LMAgentRendersThemes, false)) {
    LMStatusSet(LMStatusAgentRendersThemes, @NO);
    LMStatusEvent(@"iconservicesagent rendered %@ without the theme, rendering theme icons here", LMThemedIconIdentifier(icon));
  }
}

// iconservicesagent renders one request at a time, so do we
static NSLock *LMRenderLock(void) {
  static NSLock *lock;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    lock = [NSLock new];
  });
  return lock;
}

// what iconservicesagent does with a request, done here. The theme provider comes from the hooks below.
static IFImage *LMRenderHere(ISConcreteIcon *icon, id descriptor) {
  Class requestClass = objc_getClass("ISGenerationRequest");
  if (!descriptor || ![requestClass instancesRespondToSelector:@selector(generateImage)]) return nil;
  NSLock *lock = LMRenderLock();
  IFImage *image = nil;
  [lock lock];
  @try {
    ISGenerationRequest *request = [requestClass new];
    [request setImageDescriptor:descriptor];
    [request setIcon:icon];
    image = [request generateImage];
  } @catch (NSException *exception) {
    LMStatusEvent(@"rendering %@ failed: %@", LMThemedIconIdentifier(icon), exception.reason);
  }
  [lock unlock];
  if (LMRenderedWithTheme(image)) {
    LMStatusCount(LMCounterLocalRendered);
    return image;
  }
  LMStatusCount(LMCounterLocalFailed);
  if (LMStatusCounterValue(LMCounterLocalFailed) <= 5) LMStatusEvent(@"couldn't render %@ with the theme", LMThemedIconIdentifier(icon));
  return image;
}

// For SpringBoard (LumenBoardSpringBoard looks it up with dlsym): the app's own icon, without any theme,
// so the icon shape and effects can be drawn into it. masked: with the iOS shape. NULL if it can't be rendered.
__attribute__((visibility("default"))) CGImageRef LMCoreCopyStockIconImage(NSString *bundleIdentifier, CGFloat points, CGFloat scale, BOOL masked) {
  Class iconClass = objc_getClass("ISBundleIdentifierIcon");
  Class descriptorClass = objc_getClass("ISImageDescriptor");
  Class requestClass = objc_getClass("ISGenerationRequest");
  if (!bundleIdentifier.length || ![iconClass instancesRespondToSelector:@selector(initWithBundleIdentifier:)] || ![descriptorClass instancesRespondToSelector:@selector(initWithSize:scale:)] || ![requestClass instancesRespondToSelector:@selector(generateImage)]) return NULL;
  CGImageRef result = NULL;
  NSLock *lock = LMRenderLock();
  [lock lock];
  LMRenderingStock = YES;
  @try {
    @autoreleasepool {
      ISConcreteIcon *icon = [[iconClass alloc] initWithBundleIdentifier:bundleIdentifier];
      ISImageDescriptor *descriptor = [[descriptorClass alloc] initWithSize:CGSizeMake(points, points) scale:scale];
      if ([descriptor respondsToSelector:@selector(setShouldApplyMask:)]) [descriptor setShouldApplyMask:masked];
      ISGenerationRequest *request = [requestClass new];
      [request setImageDescriptor:descriptor];
      [request setIcon:icon];
      IFImage *image = icon ? [request generateImage] : nil;
      CGImageRef cgImage = [image respondsToSelector:@selector(CGImage)] ? [image CGImage] : NULL;
      if (cgImage) result = CGImageRetain(cgImage);
    }
  } @catch (NSException *exception) {
    LMStatusEvent(@"rendering the stock icon of %@ failed: %@", bundleIdentifier, exception.reason);
  }
  LMRenderingStock = NO;
  [lock unlock];
  return result;
}

static void LMMapDidChange(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
  // iconservicesagent was restarted with the new map, give it another chance
  if (!atomic_exchange(&LMAgentRendersThemes, true)) LMStatusSet(LMStatusAgentRendersThemes, @YES);
}

// TEST BUILD: what the store hands back for tinted/clear requests of the test apps (once per app and kind)
static void LMLogStoreLookup(ISConcreteIcon *icon, id descriptor, IFImage *image) {
  NSString *bundleIdentifier = LMThemedIconIdentifier(icon);
  if (!bundleIdentifier || ![@[@"com.apple.calculator", @"com.apple.camera", @"com.apple.appstore", @"com.apple.findmy"] containsObject:bundleIdentifier]) return;
  long long variant = [descriptor respondsToSelector:@selector(appearanceVariant)] ? ((long long (*)(id, SEL))objc_msgSend)(descriptor, @selector(appearanceVariant)) : 0;
  if (variant != 2 && variant != 3) return;
  static NSMutableSet *seen;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ seen = [NSMutableSet new]; });
  NSString *key = [NSString stringWithFormat:@"%@/%lld/%d", bundleIdentifier, variant, image ? 1 : 0];
  @synchronized (seen) {
    if ([seen containsObject:key]) return;
    [seen addObject:key];
  }
  LMStatusEvent(@"store lookup %@ variant=%lld: %@", bundleIdentifier, variant, image ? (LMRenderedWithTheme(image) ? @"themed image" : @"stock image") : @"nothing");
}

#pragma mark - Hooks

%group Icons

// requests for icons with a themed digest, made in this process
%hook ISConcreteIcon

// cached by an iconservicesagent without LumenBoard: the stock icon under the themed digest
- (id)_imageFromStoreForDescriptor:(id)descriptor {
  IFImage *image = %orig;
  LMLogStoreLookup(self, descriptor, image);
  if (!image || !LMThemedIconIdentifier(self) || LMRenderedWithTheme(image)) return image;
  LMAgentMissedTheme(self);
  return nil;
}

- (id)generateImageWithDescriptor:(id)descriptor {
  if (!LMThemedIconIdentifier(self)) return %orig;
  if (LMTestStock(self, descriptor)) return LMTestSwap(self, descriptor, %orig);
  IFImage *own = LMOwnTintedImage(self, descriptor);
  if (own) return own;
  IFImage *image = nil;
  if (atomic_load(&LMAgentRendersThemes)) {
    image = %orig;
    if (LMRenderedWithTheme(image)) {
      LMStatusCount(LMCounterAgentThemed);
      return image;
    }
    LMAgentMissedTheme(self);
  }
  IFImage *rendered = LMRenderHere(self, descriptor);
  if (rendered) return rendered;
  return image ? : %orig;
}

- (void)generateImageWithDescriptor:(id)descriptor completion:(void (^)(id image))completion {
  if (!LMThemedIconIdentifier(self) || !completion) {
    %orig;
    return;
  }
  if (LMTestStock(self, descriptor)) {
    ISConcreteIcon *testIcon = self;
    id testDescriptor = [descriptor copy];
    %orig(descriptor, ^(id image) { completion(LMTestSwap(testIcon, testDescriptor, image)); });
    return;
  }
  ISConcreteIcon *icon = self;
  id request = [descriptor copy];
  IFImage *own = LMOwnTintedImage(self, descriptor);
  if (own) {
    completion(own);
    return;
  }
  void (^checked)(id) = ^(id image) {
    if (LMRenderedWithTheme(image)) {
      LMStatusCount(LMCounterAgentThemed);
      completion(image);
      return;
    }
    LMAgentMissedTheme(icon);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      IFImage *rendered = LMRenderHere(icon, request);
      completion(rendered ? : image);
    });
  };
  %orig(descriptor, checked);
}

%end

%hook ISBundleIdentifierIcon

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier {
  self = %orig;
  LMMarkThemed(self, bundleIdentifier);
  return self;
}

// allowFallback NO = -makeSymbolResourceProvider, leave it alone
- (id)_makeResourceProviderAllowIconResourceFallback:(BOOL)allowFallback {
  if (allowFallback) {
    NSString *bundleIdentifier = [self bundleIdentifier];
    ISResourceProvider *provider = LMProviderForRequest(self, bundleIdentifier, ^ISConcreteIcon *{
      return [[%c(ISBundleIdentifierIcon) alloc] initWithBundleIdentifier:bundleIdentifier];
    });
    if (provider) return provider;
  }
  return %orig;
}

%end

%hook ISBundleIcon

- (instancetype)initWithBundleURL:(NSURL *)url type:(NSString *)type tag:(NSString *)tag tagClass:(NSString *)tagClass {
  self = %orig;
  // no type/tag = the app icon of the bundle
  if (!type && !(tag && tagClass)) LMMarkThemed(self, LMBundleIdentifierForAppURL(url));
  return self;
}

- (id)_makeAppResourceProvider {
  NSURL *url = [self url];
  ISResourceProvider *provider = LMProviderForRequest(self, LMBundleIdentifierForAppURL(url), ^ISConcreteIcon *{
    return [[%c(ISBundleIcon) alloc] initWithBundleURL:url type:nil tag:nil tagClass:nil];
  });
  return provider ? : %orig;
}

%end

%hook ISApplicationIdentityIcon

- (instancetype)initWithApplicationIdentity:(id)identity {
  self = %orig;
  LMMarkThemed(self, LMBundleIdentifierForIdentity(identity));
  return self;
}

- (id)_makeResourceProviderAllowIconResourceFallback:(BOOL)allowFallback {
  Class identityClass = objc_getClass("LSApplicationIdentity");
  NSString *identityString = [self identityString];
  if (allowFallback && identityString && [identityClass instancesRespondToSelector:@selector(initWithIdentityString:)]) {
    id identity = [[identityClass alloc] initWithIdentityString:identityString];
    ISResourceProvider *provider = LMProviderForRequest(self, LMBundleIdentifierForIdentity(identity), ^ISConcreteIcon *{
      return [[%c(ISApplicationIdentityIcon) alloc] initWithApplicationIdentity:identity];
    });
    if (provider) return provider;
  }
  return %orig;
}

%end

%end

#pragma mark - Setup

static Class LMSubclass(Class base, const char *name) {
  Class existing = objc_getClass(name);
  if (existing) return existing;
  Class subclass = base ? objc_allocateClassPair(base, name, 0) : Nil;
  return subclass;
}

static void LMInstallIconHooks(void) {
  if (LMHooksInstalled) return;
  Class concreteIcon = objc_getClass("ISConcreteIcon");
  Class providerBase = objc_getClass("ISResourceProvider");
  if (!concreteIcon) return;
  if (!providerBase || !objc_getClass("ISBundleIdentifierIcon") || !objc_getClass("IFImage") || !objc_getClass("IFImageBag")) {
    LMStatusEvent(@"IconServices classes missing, icons stay stock");
    return;
  }
  // no _digest, no way to keep themed and stock icons apart
  Ivar digest = class_getInstanceVariable(concreteIcon, "_digest");
  if (!digest || ![providerBase instancesRespondToSelector:@selector(initWithResource:templateResource:)]) {
    LMStatusEvent(@"ISConcreteIcon has no _digest, icons stay stock");
    return;
  }
  LMHooksInstalled = YES;
  LMDigestIvar = digest;
  LMImageBags = [NSCache new];
  LMImageBags.countLimit = 300;
  LMImageBags.totalCostLimit = 48 * 1024 * 1024;
  LMAppURLIdentifiers = [NSCache new];

  Class provider = LMSubclass(providerBase, "LMThemeIconProvider");
  if (provider && !objc_getClass("LMThemeIconProvider")) {
    class_addMethod(provider, @selector(configureProviderFromDescriptor:), (IMP)LMProviderConfigure, "v@:@");
    objc_registerClassPair(provider);
  }
  LMProviderClass = provider;

  Class appRecipe = objc_getClass("ISiOSAppRecipe");
  Class recipe = LMSubclass(appRecipe, "LMThemeIconRecipe");
  if (recipe && !objc_getClass("LMThemeIconRecipe")) {
    class_addMethod(recipe, @selector(shouldApplyMask), (IMP)LMRecipeShouldApplyMask, "B@:");
    SEL primaryEffect = @selector(primaryResourceEffectReturningBackgroundContentOverride:);
    if (class_getInstanceMethod(appRecipe, primaryEffect)) class_addMethod(recipe, primaryEffect, (IMP)LMRecipePrimaryEffect, "@@:^@");
    objc_registerClassPair(recipe);
  }
  LMRecipeClass = recipe;

  %init(Icons);
  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMMapDidChange, CFSTR(LMNotifyMapChanged), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
  LMStatusSet(LMStatusHooksInstalled, @YES);
  if (![[NSProcessInfo processInfo].processName isEqualToString:@"iconservicesagent"]) LMStatusSet(LMStatusAgentRendersThemes, @YES);
}

static void LMImageAdded(const struct mach_header *header, intptr_t slide) {
  if (LMHooksInstalled) return;
  Dl_info info;
  if (!dladdr(header, &info) || !info.dli_fname || !strstr(info.dli_fname, "/IconServices.framework/")) return;
  // IconServices got loaded after us
  dispatch_async(dispatch_get_main_queue(), ^{ LMInstallIconHooks(); });
}

%ctor {
  @autoreleasepool {
    if (![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){17, 0, 0}]) return;
    LMStatusSet(LMStatusLoaded, [NSDate date]);
    LMStatusSet(LMStatusHooksInstalled, @NO);
    LMInstallIconHooks();
    if (!LMHooksInstalled) _dyld_register_func_for_add_image(LMImageAdded);
  }
}
