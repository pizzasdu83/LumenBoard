#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Unpacks themes from a zip into LMImportedThemesDirectory (the themes folder belongs to root, the app can't write there).
@interface LMZipImporter : NSObject

// The zip can hold one theme (a folder with IconBundles / Icons, or just those folders) or several.
// Returns the folder names of the themes ("Name.theme"). Slow for big zips, don't call it on the main thread.
+ (nullable NSArray<NSString *> *)importThemesFromZipAtPath:(NSString *)path error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
