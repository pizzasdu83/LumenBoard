#import "LMZipImporter.h"
#import "LMAppDelegate.h"
#import "../Shared/LMShared.h"
#include <sys/stat.h>
#include <zlib.h>

static const uint32_t LMMaxFileSize = 64 * 1024 * 1024;
static const uint64_t LMMaxTotalSize = 1024ull * 1024 * 1024;
static const NSUInteger LMMaxFiles = 50000;

static uint16_t LMRead16(const uint8_t *p) {
  return (uint16_t)(p[0] | (p[1] << 8));
}

static uint32_t LMRead32(const uint8_t *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static NSError *LMZipError(NSString *message) {
  return [NSError errorWithDomain:@"LumenBoard" code:3 userInfo:@{ NSLocalizedDescriptionKey : message }];
}

@interface LMZipEntry : NSObject
@property (nonatomic, copy) NSArray<NSString *> *components;
@property (nonatomic) uint16_t method;
@property (nonatomic) uint32_t crc, compressedSize, size, localOffset;
@end

@implementation LMZipEntry
@end

// writes one file of the zip to destination, checks size and CRC
static BOOL LMExtractEntry(const uint8_t *bytes, NSUInteger length, LMZipEntry *entry, NSString *destination) {
  if ((uint64_t)entry.localOffset + 30 > length || LMRead32(bytes + entry.localOffset) != 0x04034b50) return NO;
  const uint8_t *local = bytes + entry.localOffset;
  uint64_t dataStart = (uint64_t)entry.localOffset + 30 + LMRead16(local + 26) + LMRead16(local + 28);
  if (dataStart + entry.compressedSize > length) return NO;
  const uint8_t *data = bytes + dataStart;

  FILE *file = fopen(destination.fileSystemRepresentation, "wb");
  if (!file) return NO;
  uLong crc = crc32(0L, Z_NULL, 0);
  BOOL ok = YES;
  if (entry.method == 0) {
    ok = entry.compressedSize == entry.size && fwrite(data, 1, entry.size, file) == entry.size;
    if (ok) crc = crc32(crc, data, entry.size);
  } else if (entry.method == 8) {
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
      ok = NO;
    } else {
      stream.next_in = (Bytef *)data;
      stream.avail_in = entry.compressedSize;
      uint8_t buffer[65536];
      int result;
      do {
        stream.next_out = buffer;
        stream.avail_out = sizeof(buffer);
        result = inflate(&stream, Z_NO_FLUSH);
        if (result != Z_OK && result != Z_STREAM_END) { ok = NO; break; }
        size_t produced = sizeof(buffer) - stream.avail_out;
        // a file that unpacks to more than it says it is
        if (stream.total_out > entry.size || fwrite(buffer, 1, produced, file) != produced) { ok = NO; break; }
        crc = crc32(crc, buffer, (uInt)produced);
      } while (result != Z_STREAM_END);
      if (ok && stream.total_out != entry.size) ok = NO;
      inflateEnd(&stream);
    }
  } else {
    ok = NO;
  }
  fclose(file);
  if (ok && (uint32_t)crc != entry.crc) ok = NO;
  if (!ok) {
    unlink(destination.fileSystemRepresentation);
    return NO;
  }
  chmod(destination.fileSystemRepresentation, 0644);
  return YES;
}

static NSString *LMThemeFolderName(NSString *base) {
  NSString *name = base;
  while ([name hasPrefix:@"."]) name = [name substringFromIndex:1];
  if ([name.pathExtension caseInsensitiveCompare:@"theme"] == NSOrderedSame) name = name.stringByDeletingPathExtension;
  name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (!name.length) name = @"Imported";
  return [name stringByAppendingString:@".theme"];
}

@implementation LMZipImporter

+ (NSArray<NSString *> *)importThemesFromZipAtPath:(NSString *)path error:(NSError **)error {
  NSData *zip = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
  if (!zip) return nil;
  const uint8_t *bytes = zip.bytes;
  NSUInteger length = zip.length;

  // end of central directory record, the last 22+ bytes
  NSInteger endRecord = -1;
  for (NSInteger index = (NSInteger)length - 22; index >= 0 && index >= (NSInteger)length - 22 - 65535; index--) {
    if (LMRead32(bytes + index) == 0x06054b50) { endRecord = index; break; }
  }
  if (endRecord < 0) {
    if (error) *error = LMZipError(LMLocalized(@"This isn't a zip file."));
    return nil;
  }
  uint32_t count = LMRead16(bytes + endRecord + 10), directorySize = LMRead32(bytes + endRecord + 12), directoryOffset = LMRead32(bytes + endRecord + 16);
  if (count == 0xFFFF || directoryOffset == 0xFFFFFFFF || (uint64_t)directoryOffset + directorySize > length) {
    if (error) *error = LMZipError(LMLocalized(@"This zip can't be read."));
    return nil;
  }

  // the files of the zip, without the ones that can't be trusted or don't matter
  NSMutableArray<LMZipEntry *> *entries = [NSMutableArray new];
  NSUInteger position = directoryOffset;
  for (uint32_t index = 0; index < count; index++) {
    if (position + 46 > length || LMRead32(bytes + position) != 0x02014b50) {
      if (error) *error = LMZipError(LMLocalized(@"This zip can't be read."));
      return nil;
    }
    const uint8_t *header = bytes + position;
    uint16_t flags = LMRead16(header + 8), nameLength = LMRead16(header + 28), extraLength = LMRead16(header + 30), commentLength = LMRead16(header + 32);
    if (position + 46 + nameLength > length) {
      if (error) *error = LMZipError(LMLocalized(@"This zip can't be read."));
      return nil;
    }
    NSString *name = [[NSString alloc] initWithBytes:header + 46 length:nameLength encoding:NSUTF8StringEncoding] ? : [[NSString alloc] initWithBytes:header + 46 length:nameLength encoding:NSISOLatin1StringEncoding];
    LMZipEntry *entry = [LMZipEntry new];
    entry.method = LMRead16(header + 10);
    entry.crc = LMRead32(header + 16);
    entry.compressedSize = LMRead32(header + 20);
    entry.size = LMRead32(header + 24);
    entry.localOffset = LMRead32(header + 42);
    position += 46 + nameLength + extraLength + commentLength;

    name = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    if (!name.length || [name hasSuffix:@"/"]) continue; // folders are made when a file needs them
    NSMutableArray *components = [NSMutableArray new];
    BOOL unsafe = NO;
    for (NSString *component in [name componentsSeparatedByString:@"/"]) {
      if (!component.length || [component isEqualToString:@"."]) continue;
      if ([component isEqualToString:@".."]) unsafe = YES;
      [components addObject:component];
    }
    NSString *file = components.lastObject;
    if (unsafe || !components.count || [components.firstObject isEqualToString:@"__MACOSX"] || [file hasPrefix:@"."]) continue;
    // only the icons matter
    if ([file.pathExtension caseInsensitiveCompare:@"png"] != NSOrderedSame) continue;
    if (flags & 1) {
      if (error) *error = LMZipError(LMLocalized(@"This zip is password protected."));
      return nil;
    }
    entry.components = components;
    [entries addObject:entry];
  }

  // a theme is whatever has an IconBundles or Icons folder: group the files by the folder that holds it
  NSMutableDictionary<NSString *, NSMutableArray<LMZipEntry *> *> *roots = [NSMutableDictionary new];
  NSMutableDictionary<NSString *, NSNumber *> *rootDepths = [NSMutableDictionary new];
  for (LMZipEntry *entry in entries) {
    NSArray *components = entry.components;
    for (NSUInteger index = 0; index + 1 < components.count; index++) {
      NSString *folder = [components[index] lowercaseString];
      if (![folder isEqualToString:@"iconbundles"] && ![folder isEqualToString:@"icons"]) continue;
      NSString *root = [[components subarrayWithRange:NSMakeRange(0, index)] componentsJoinedByString:@"/"];
      if (!roots[root]) roots[root] = [NSMutableArray new];
      [roots[root] addObject:entry];
      rootDepths[root] = @(index);
      break;
    }
  }
  // the effects and the icon mask of those themes come along
  for (LMZipEntry *entry in entries) {
    NSArray *components = entry.components;
    for (NSString *root in roots.allKeys) {
      NSUInteger depth = [rootDepths[root] unsignedIntegerValue];
      if (components.count <= depth + 1 || ![[[components subarrayWithRange:NSMakeRange(0, depth)] componentsJoinedByString:@"/"] isEqualToString:root]) continue;
      NSString *folder = [components[depth] lowercaseString];
      BOOL effects = [folder isEqualToString:@"anemoneeffects"];
      BOOL mask = [folder isEqualToString:@"bundles"] && components.count > depth + 2 && [[components[depth + 1] lowercaseString] isEqualToString:@"com.apple.mobileicons.framework"];
      if ((effects || mask) && ![roots[root] containsObject:entry]) [roots[root] addObject:entry];
    }
  }
  if (!roots.count) {
    if (error) *error = LMZipError(LMLocalized(@"No theme found in this zip. A theme has an IconBundles or Icons folder."));
    return nil;
  }

  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *importedDirectory = LMImportedThemesDirectory;
  NSString *temporary = [importedDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@".importing-%@", [NSUUID UUID].UUIDString]];
  if (![fileManager createDirectoryAtPath:temporary withIntermediateDirectories:YES attributes:nil error:error]) return nil;
  chmod(importedDirectory.fileSystemRepresentation, 0755);

  NSString *zipName = path.lastPathComponent.stringByDeletingPathExtension;
  NSMutableArray<NSString *> *names = [NSMutableArray new];
  uint64_t total = 0;
  NSUInteger files = 0;
  NSError *failure;
  for (NSString *root in [roots.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
    NSString *name = LMThemeFolderName(root.length ? root.lastPathComponent : zipName);
    // a theme in /Library/Themes has the same name: keep both
    if ([fileManager fileExistsAtPath:[LMThemesDirectory stringByAppendingPathComponent:name]]) name = LMThemeFolderName([name.stringByDeletingPathExtension stringByAppendingString:@" (imported)"]);
    NSString *unique = name;
    for (int number = 2; [names containsObject:unique]; number++) unique = LMThemeFolderName([NSString stringWithFormat:@"%@ %d", name.stringByDeletingPathExtension, number]);
    name = unique;

    NSString *themeTemporary = [temporary stringByAppendingPathComponent:name];
    NSUInteger depth = [rootDepths[root] unsignedIntegerValue];
    for (LMZipEntry *entry in roots[root]) {
      total += entry.size;
      if (entry.size > LMMaxFileSize || total > LMMaxTotalSize || ++files > LMMaxFiles) {
        failure = LMZipError(LMLocalized(@"The zip is too large."));
        break;
      }
      NSArray *rest = [entry.components subarrayWithRange:NSMakeRange(depth, entry.components.count - depth)];
      NSString *destination = [themeTemporary stringByAppendingPathComponent:[rest componentsJoinedByString:@"/"]];
      if (![fileManager createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil] || !LMExtractEntry(bytes, length, entry, destination)) {
        failure = LMZipError([NSString stringWithFormat:LMLocalized(@"Couldn't unpack %@."), entry.components.lastObject]);
        break;
      }
    }
    if (failure) break;

    // replaces an earlier import of the same theme
    NSString *final = [importedDirectory stringByAppendingPathComponent:name];
    [fileManager removeItemAtPath:final error:nil];
    if (![fileManager moveItemAtPath:themeTemporary toPath:final error:&failure]) break;
    chmod(final.fileSystemRepresentation, 0755);
    [names addObject:name];
  }
  [fileManager removeItemAtPath:temporary error:nil];
  if (failure && !names.count) {
    if (error) *error = failure;
    return nil;
  }
  return names;
}

@end
