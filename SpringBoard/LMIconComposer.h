#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// Draws an icon shape and a theme's underlay/overlay into app icons and saves them as png.
@interface LMIconComposer : NSObject

// shape: LMIconShape*. maskPath only counts for LMIconShapeThemeMask, a missing mask falls back to the theme's shape.
- (instancetype)initWithShape:(NSString *)shape maskPath:(nullable NSString *)maskPath effects:(NSDictionary<NSString *, NSString *> *)effects;

// the shape that's really used
@property (nonatomic, readonly) NSString *shape;
// YES for a custom shape drawn into the icons (circle, rounded square, square, teardrop, theme mask), NO for the iOS shape and the theme's own
@property (nonatomic, readonly) BOOL drawsShape;
// changes how icons look beyond what IconServices does itself: a custom shape, or an underlay/overlay
@property (nonatomic, readonly) BOOL changesIcons;
// for cache keys: shape, mask and effect files with their stamps
@property (nonatomic, readonly) NSString *signature;
// edge length of the pngs
@property (nonatomic, readonly) size_t pixelSize;

// effects: draw the underlay/overlay (not for dark/tinted artwork). NO if the png couldn't be written.
- (BOOL)writeIconWithArtwork:(CGImageRef)artwork effects:(BOOL)effects toPath:(NSString *)path;
// same, artwork read from a png
- (BOOL)writeIconWithArtworkAtPath:(NSString *)artworkPath effects:(BOOL)effects toPath:(NSString *)path;

// background: goes behind the artwork, inside the shape (a map background: Mode, Color, Color2, Angle, Image as a jailbreak path). Only
// with a custom shape, the home screen draws the background itself behind the iOS shape. nil: none.
- (BOOL)writeIconWithArtwork:(CGImageRef)artwork effects:(BOOL)effects background:(nullable NSDictionary *)background toPath:(NSString *)path;
- (BOOL)writeIconWithArtworkAtPath:(NSString *)artworkPath effects:(BOOL)effects background:(nullable NSDictionary *)background toPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
