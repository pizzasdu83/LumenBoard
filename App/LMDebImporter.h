#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Takes the icon themes out of a .deb (what a package manager would install) into LMImportedThemesDirectory.
// A .deb can hold several themes, only the ones with an IconBundles or Icons folder are icon themes. The other ones
// (sounds, status bar, dock...) can't be used by LumenBoard and are counted in skipped.
@interface LMDebImporter : NSObject

// Returns the folder names of the imported themes ("Name.theme"). Needs dpkg-deb (it reads gz, xz, zstd...).
// Slow for big packages, don't call it on the main thread.
+ (nullable NSArray<NSString *> *)importThemesFromDebAtPath:(NSString *)path skipped:(NSUInteger *)skipped error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
