#import "LMDebImporter.h"
#import "LMAppDelegate.h"
#import "../Shared/LMShared.h"
#include <fcntl.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static const NSUInteger LMMaxFiles = 50000;

static NSError *LMDebError(NSString *message) {
  return [NSError errorWithDomain:@"LumenBoard" code:4 userInfo:@{ NSLocalizedDescriptionKey : message }];
}

static NSString *LMThemeFolderName(NSString *base) {
  NSString *name = base;
  while ([name hasPrefix:@"."]) name = [name substringFromIndex:1];
  if ([name.pathExtension caseInsensitiveCompare:@"theme"] == NSOrderedSame) name = name.stringByDeletingPathExtension;
  name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (!name.length) name = @"Imported";
  return [name stringByAppendingString:@".theme"];
}

static BOOL LMIsRealFolder(NSString *path) {
  BOOL isDirectory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) return NO;
  // a link could lead out of the package
  return ![[[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileType] isEqualToString:NSFileTypeSymbolicLink];
}

static NSString *LMDpkgDebPath(void) {
  for (NSString *candidate in @[LMRootPath(@"/usr/bin/dpkg-deb"), @"/var/jb/usr/bin/dpkg-deb", @"/usr/bin/dpkg-deb"]) {
    if (access(candidate.fileSystemRepresentation, X_OK) == 0) return candidate;
  }
  return nil;
}

// every *.theme folder in the unpacked package, wherever it is (/Library/Themes, /var/jb/Library/Themes...)
static void LMCollectThemes(NSString *directory, NSUInteger depth, NSMutableArray<NSString *> *found) {
  if (depth > 8) return;
  for (NSString *item in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil]) {
    NSString *path = [directory stringByAppendingPathComponent:item];
    if (!LMIsRealFolder(path)) continue;
    if ([item.pathExtension caseInsensitiveCompare:@"theme"] == NSOrderedSame) [found addObject:path];
    else LMCollectThemes(path, depth + 1, found);
  }
}

@implementation LMDebImporter

+ (NSArray<NSString *> *)importThemesFromDebAtPath:(NSString *)path skipped:(NSUInteger *)skipped error:(NSError **)error {
  NSString *dpkgDeb = LMDpkgDebPath();
  if (!dpkgDeb) {
    if (error) *error = LMDebError(LMLocalized(@"dpkg-deb isn't installed. Install dpkg from your package manager."));
    return nil;
  }

  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *importedDirectory = LMImportedThemesDirectory;
  NSString *temporary = [importedDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@".importing-%@", [NSUUID UUID].UUIDString]];
  NSString *unpacked = [temporary stringByAppendingPathComponent:@"unpacked"];
  NSString *output = [temporary stringByAppendingPathComponent:@"themes"];
  NSString *logPath = [temporary stringByAppendingPathComponent:@"dpkg-deb.log"];
  if (![fileManager createDirectoryAtPath:unpacked withIntermediateDirectories:YES attributes:nil error:error]) return nil;
  [fileManager createDirectoryAtPath:output withIntermediateDirectories:YES attributes:nil error:nil];
  chmod(importedDirectory.fileSystemRepresentation, 0755);

  // dpkg-deb starts tar, xz... from the PATH, and the app doesn't have the jailbreak folders in it
  NSString *pathVariable = [NSString stringWithFormat:@"PATH=%@:%@:/usr/bin:/bin", LMRootPath(@"/usr/bin"), LMRootPath(@"/bin")];
  NSString *tmpVariable = [@"TMPDIR=" stringByAppendingString:temporary];
  char *environment[] = { (char *)pathVariable.UTF8String, (char *)tmpVariable.UTF8String, (char *)"HOME=/var/mobile", NULL };
  char *arguments[] = { (char *)"dpkg-deb", (char *)"-x", (char *)path.fileSystemRepresentation, (char *)unpacked.fileSystemRepresentation, NULL };

  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, logPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
  pid_t pid;
  int spawnError = posix_spawn(&pid, dpkgDeb.fileSystemRepresentation, &actions, NULL, arguments, environment);
  posix_spawn_file_actions_destroy(&actions);
  int status = 0;
  if (spawnError == 0) waitpid(pid, &status, 0);
  BOOL unpackFailed = spawnError != 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0;

  NSMutableArray<NSString *> *themes = [NSMutableArray new];
  LMCollectThemes(unpacked, 0, themes);
  // dpkg-deb can complain (about the permissions of a folder, say) after unpacking everything: that is fine if themes came out
  if (unpackFailed && !themes.count) {
    NSString *log = [[NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (log.length > 300) log = [log substringToIndex:300];
    NSString *reason = log.length ? log : (spawnError ? [NSString stringWithUTF8String:strerror(spawnError)] : [NSString stringWithFormat:@"exit %d", WEXITSTATUS(status)]);
    [fileManager removeItemAtPath:temporary error:nil];
    if (error) *error = LMDebError([NSString stringWithFormat:LMLocalized(@"Couldn't open this package: %@"), reason]);
    return nil;
  }

  NSMutableArray<NSString *> *names = [NSMutableArray new];
  NSUInteger skippedCount = 0, files = 0;
  for (NSString *theme in [themes sortedArrayUsingSelector:@selector(compare:)]) {
    // only IconBundles and Icons are used, the rest of the theme (sounds, status bar, dock...) is left out
    NSMutableArray<NSString *> *iconFolders = [NSMutableArray new];
    NSMutableArray<NSString *> *extraFolders = [NSMutableArray new]; // effects and the icon mask, relative to the theme
    for (NSString *child in [fileManager contentsOfDirectoryAtPath:theme error:nil]) {
      NSString *lowercase = child.lowercaseString;
      NSString *childPath = [theme stringByAppendingPathComponent:child];
      if (!LMIsRealFolder(childPath)) continue;
      if ([lowercase isEqualToString:@"iconbundles"] || [lowercase isEqualToString:@"icons"]) [iconFolders addObject:child];
      else if ([lowercase isEqualToString:@"anemoneeffects"]) [extraFolders addObject:child];
      else if ([lowercase isEqualToString:@"bundles"]) {
        // the icon mask lives in Bundles/com.apple.mobileicons.framework, the rest of Bundles is not used
        for (NSString *bundle in [fileManager contentsOfDirectoryAtPath:childPath error:nil]) {
          if ([bundle.lowercaseString isEqualToString:@"com.apple.mobileicons.framework"] && LMIsRealFolder([childPath stringByAppendingPathComponent:bundle])) [extraFolders addObject:[child stringByAppendingPathComponent:bundle]];
        }
      }
    }
    if (!iconFolders.count) {
      skippedCount++;
      continue;
    }

    NSString *name = LMThemeFolderName(theme.lastPathComponent);
    // a theme in /Library/Themes has the same name: keep both
    if ([fileManager fileExistsAtPath:[LMThemesDirectory stringByAppendingPathComponent:name]]) name = LMThemeFolderName([name.stringByDeletingPathExtension stringByAppendingString:@" (imported)"]);
    NSString *unique = name;
    for (int number = 2; [names containsObject:unique]; number++) unique = LMThemeFolderName([NSString stringWithFormat:@"%@ %d", name.stringByDeletingPathExtension, number]);
    name = unique;

    NSString *themeOutput = [output stringByAppendingPathComponent:name];
    NSUInteger copied = 0;
    for (NSString *folder in iconFolders) {
      NSString *folderPath = [theme stringByAppendingPathComponent:folder];
      for (NSString *relative in [fileManager enumeratorAtPath:folderPath]) {
        if ([relative.pathExtension caseInsensitiveCompare:@"png"] != NSOrderedSame || [relative.lastPathComponent hasPrefix:@"."]) continue;
        NSString *source = [folderPath stringByAppendingPathComponent:relative];
        if (![[[fileManager attributesOfItemAtPath:source error:nil] fileType] isEqualToString:NSFileTypeRegular]) continue;
        if (++files > LMMaxFiles) {
          [fileManager removeItemAtPath:temporary error:nil];
          if (error) *error = LMDebError(LMLocalized(@"The package is too large."));
          return nil;
        }
        NSString *destination = [themeOutput stringByAppendingPathComponent:[folder stringByAppendingPathComponent:relative]];
        [fileManager createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        if ([fileManager copyItemAtPath:source toPath:destination error:nil]) {
          chmod(destination.fileSystemRepresentation, 0644);
          copied++;
        }
      }
    }
    if (!copied) {
      skippedCount++;
      continue;
    }
    // effects and icon mask: pictures only
    for (NSString *folder in extraFolders) {
      NSString *folderPath = [theme stringByAppendingPathComponent:folder];
      for (NSString *relative in [fileManager enumeratorAtPath:folderPath]) {
        if ([relative.pathExtension caseInsensitiveCompare:@"png"] != NSOrderedSame || [relative.lastPathComponent hasPrefix:@"."]) continue;
        NSString *source = [folderPath stringByAppendingPathComponent:relative];
        if (![[[fileManager attributesOfItemAtPath:source error:nil] fileType] isEqualToString:NSFileTypeRegular] || ++files > LMMaxFiles) continue;
        NSString *destination = [themeOutput stringByAppendingPathComponent:[folder stringByAppendingPathComponent:relative]];
        [fileManager createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        if ([fileManager copyItemAtPath:source toPath:destination error:nil]) chmod(destination.fileSystemRepresentation, 0644);
      }
    }

    // replaces an earlier import of the same theme
    NSString *final = [importedDirectory stringByAppendingPathComponent:name];
    [fileManager removeItemAtPath:final error:nil];
    if (![fileManager moveItemAtPath:themeOutput toPath:final error:nil]) continue;
    chmod(final.fileSystemRepresentation, 0755);
    [names addObject:name];
  }
  [fileManager removeItemAtPath:temporary error:nil];
  if (skipped) *skipped = skippedCount;
  if (!names.count) {
    if (error) *error = LMDebError(LMLocalized(@"No icon theme found in this package. A theme has an IconBundles or Icons folder."));
    return nil;
  }
  return names;
}

@end
