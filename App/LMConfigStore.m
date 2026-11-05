#import "LMConfigStore.h"
#include <sys/stat.h>

// no duplicates, always in the same order, so the same choice is always the same config
static NSArray<NSString *> *LMNormalizedList(NSArray<NSString *> *list, BOOL lowercase) {
  NSMutableSet *set = [NSMutableSet new];
  for (NSString *item in list) if ([item isKindOfClass:[NSString class]] && item.length) [set addObject:lowercase ? item.lowercaseString : item];
  return [set.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

@implementation LMConfigStore {
  NSDictionary *_appliedConfig;
}

+ (instancetype)sharedStore {
  static LMConfigStore *store;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    store = [self new];
  });
  return store;
}

- (instancetype)init {
  if ((self = [super init])) {
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:LMConfigPath] ? : @{};
    NSArray *themes = config[LMConfigEnabledThemes];
    _enabledThemes = [themes isKindOfClass:[NSArray class]] ? [themes copy] : @[];
    _iconShape = LMIconShapeFromConfig(config);
    _iconEffects = LMIconEffectsFromConfig(config);
    _keepIconsInDarkAndTinted = [config[LMConfigKeepIconsInDarkAndTinted] boolValue];
    NSArray *apps = config[LMConfigShapeApps], *shapeThemeList = config[LMConfigShapeThemes];
    _shapeApps = [apps isKindOfClass:[NSArray class]] ? [apps copy] : @[];
    _shapeThemes = [shapeThemeList isKindOfClass:[NSArray class]] ? [shapeThemeList copy] : @[];
    NSDictionary *light = config[LMConfigBackgroundLight], *dark = config[LMConfigBackgroundDark];
    _backgroundLight = [light isKindOfClass:[NSDictionary class]] ? [light copy] : @{};
    _backgroundDark = [dark isKindOfClass:[NSDictionary class]] ? [dark copy] : @{};
    NSString *revision = config[LMConfigCustomIconsRevision];
    _customIconsRevision = [revision isKindOfClass:[NSString class]] ? [revision copy] : @"";
    // what SpringBoard last applied, so the app knows about pending changes even after a restart
    NSDictionary *applied = [NSDictionary dictionaryWithContentsOfFile:LMIconMapPath][LMMapAppliedConfig];
    // maps from older versions have UseSystemIconShape instead of IconShape and don't know every key
    _appliedConfig = [applied isKindOfClass:[NSDictionary class]] ? [self normalizedConfig:applied] : [self dictionaryRepresentation];
  }
  return self;
}

// a config as it is now, with what older versions left out filled in
- (NSDictionary *)normalizedConfig:(NSDictionary *)config {
  NSArray *themes = [config[LMConfigEnabledThemes] isKindOfClass:[NSArray class]] ? config[LMConfigEnabledThemes] : @[];
  NSString *revision = [config[LMConfigCustomIconsRevision] isKindOfClass:[NSString class]] ? config[LMConfigCustomIconsRevision] : @"";
  NSDictionary *light = [config[LMConfigBackgroundLight] isKindOfClass:[NSDictionary class]] ? config[LMConfigBackgroundLight] : @{};
  NSDictionary *dark = [config[LMConfigBackgroundDark] isKindOfClass:[NSDictionary class]] ? config[LMConfigBackgroundDark] : @{};
  NSArray *shapeApps = [config[LMConfigShapeApps] isKindOfClass:[NSArray class]] ? config[LMConfigShapeApps] : @[];
  NSArray *shapeThemes = [config[LMConfigShapeThemes] isKindOfClass:[NSArray class]] ? config[LMConfigShapeThemes] : @[];
  return @{
    LMConfigEnabledThemes : themes,
    LMConfigIconShape : LMIconShapeFromConfig(config),
    LMConfigIconEffects : @(LMIconEffectsFromConfig(config)),
    LMConfigKeepIconsInDarkAndTinted : @([config[LMConfigKeepIconsInDarkAndTinted] boolValue]),
    LMConfigCustomIconsRevision : revision,
    LMConfigBackgroundLight : light,
    LMConfigBackgroundDark : dark,
    LMConfigShapeApps : shapeApps,
    LMConfigShapeThemes : shapeThemes
  };
}

- (NSDictionary *)dictionaryRepresentation {
  return @{
    LMConfigEnabledThemes : _enabledThemes ? : @[],
    LMConfigIconShape : _iconShape ? : LMIconShapeTheme,
    LMConfigIconEffects : @(_iconEffects),
    LMConfigKeepIconsInDarkAndTinted : @(_keepIconsInDarkAndTinted),
    LMConfigCustomIconsRevision : _customIconsRevision ? : @"",
    LMConfigBackgroundLight : _backgroundLight ? : @{},
    LMConfigBackgroundDark : _backgroundDark ? : @{},
    LMConfigShapeApps : _shapeApps ? : @[],
    LMConfigShapeThemes : _shapeThemes ? : @[]
  };
}

- (NSDictionary *)savedRepresentation {
  NSMutableDictionary *config = [[self dictionaryRepresentation] mutableCopy];
  // for LumenBoard versions before 1.1.0 (after a downgrade)
  config[LMConfigUseSystemIconShape] = @([_iconShape isEqualToString:LMIconShapeSystem]);
  return config;
}

- (void)setShapeApps:(NSArray<NSString *> *)shapeApps {
  _shapeApps = LMNormalizedList(shapeApps, YES);
}

- (void)setShapeThemes:(NSArray<NSString *> *)shapeThemes {
  _shapeThemes = LMNormalizedList(shapeThemes, NO);
}

- (BOOL)hasUnappliedChanges {
  return ![[self dictionaryRepresentation] isEqual:_appliedConfig];
}

- (BOOL)save:(NSError **)error {
  if (![[NSFileManager defaultManager] createDirectoryAtPath:LMDataDirectory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:[self savedRepresentation] format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
  if (!data || ![data writeToFile:LMConfigPath options:NSDataWritingAtomic error:error]) return NO;
  chmod(LMConfigPath.fileSystemRepresentation, 0644);
  return YES;
}

- (BOOL)customIconsDidChange:(NSError **)error {
  _customIconsRevision = [NSUUID UUID].UUIDString;
  return [self save:error];
}

- (void)markApplied {
  _appliedConfig = [self dictionaryRepresentation];
}

@end
