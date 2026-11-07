#import "LMThemesViewController.h"
#import "LMSettingsViewController.h"
#import "LMApplyViewController.h"
#import "LMCustomIconsViewController.h"
#import "LMZipImporter.h"
#import "LMDebImporter.h"
#import "LMHelpViewController.h"
#import "LMConfigStore.h"
#import "../Shared/LMThemeLibrary.h"
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <sys/stat.h>

typedef NS_ENUM(NSInteger, LMThemeSection) {
  LMThemeSectionActive,
  LMThemeSectionInstalled,
};

// shown in the theme previews when the theme has them
static NSArray<NSString *> *LMPreviewApps(void) {
  return @[@"com.apple.mobilesafari", @"com.apple.mobilesms", @"com.apple.mobilephone", @"com.apple.camera",
           @"com.apple.mobileslideshow", @"com.apple.preferences", @"com.apple.appstore", @"com.apple.mobilemail"];
}

// decodes only what the preview needs, theme icons are often 1024 px
static UIImage *LMThumbnail(NSString *path, CGFloat pixels) {
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
  return thumbnail;
}

// changes when the theme is reinstalled or icons are added or removed
static NSString *LMThemeStamp(NSString *theme) {
  NSString *directory = [LMThemeLibrary directoryForTheme:theme];
  NSMutableString *stamp = [NSMutableString new];
  for (NSString *folder in @[@"", @"IconBundles", @"Icons"]) {
    struct stat info;
    if (stat([directory stringByAppendingPathComponent:folder].fileSystemRepresentation, &info) == 0) [stamp appendFormat:@"%lld.%ld/", (long long)info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec];
    else [stamp appendString:@"-/"];
  }
  return stamp;
}

static UIImage *LMRenderPreview(NSArray<NSString *> *paths) {
  const CGFloat side = 44, gap = 3;
  NSUInteger count = MIN(paths.count, (NSUInteger)4);
  CGFloat tile = (count == 1) ? side : (side - gap) / 2;
  NSMutableArray<UIImage *> *icons = [NSMutableArray new];
  for (NSUInteger index = 0; index < count; index++) {
    UIImage *icon = LMThumbnail(paths[index], tile * 3);
    if (icon) [icons addObject:icon];
  }
  if (!icons.count) return nil;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
  return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    for (NSUInteger index = 0; index < icons.count; index++) {
      UIImage *icon = icons[index];
      CGRect rect = (count == 1) ? CGRectMake(0, 0, side, side) : CGRectMake((index % 2) * (tile + gap), (index / 2) * (tile + gap), tile, tile);
      CGContextSaveGState(context.CGContext);
      [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:tile * 0.225] addClip];
      [icon drawInRect:rect];
      CGContextRestoreGState(context.CGContext);
    }
  }];
}

@interface LMThemesViewController () <UIDocumentPickerDelegate>
@end

@implementation LMThemesViewController {
  NSMutableArray<NSString *> *_active;
  NSMutableArray<NSString *> *_installed;
  // theme -> preview, icon count and the stamp they were loaded with
  NSMutableDictionary<NSString *, NSDictionary *> *_details;
  NSMutableSet<NSString *> *_loading;
  dispatch_queue_t _detailsQueue;
  NSTimer *_changeTimer;
  UIButton *_applyButton;
  UIActivityIndicatorView *_importSpinner;
}

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"Slippery Board";
  _details = [NSMutableDictionary new];
  _loading = [NSMutableSet new];
  // one theme at a time, so the visible ones are done first
  _detailsQueue = dispatch_queue_create("com.xsxs18.lumenboard.theme-details", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
  [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Theme"];
  self.tableView.rowHeight = 64;
  self.tableView.allowsSelectionDuringEditing = YES;

  // a link at the bottom of the page
  UIButton *help = [UIButton buttonWithType:UIButtonTypeSystem];
  NSDictionary *linkAttributes = @{ NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle), NSFontAttributeName : [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote] };
  [help setAttributedTitle:[[NSAttributedString alloc] initWithString:LMLocalized(@"How does this work?") attributes:linkAttributes] forState:UIControlStateNormal];
  [help addTarget:self action:@selector(showHelp) forControlEvents:UIControlEventTouchUpInside];
  help.frame = CGRectMake(0, 0, 100, 60);
  self.tableView.tableFooterView = help;

  UIBarButtonItem *settingsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"] style:UIBarButtonItemStylePlain target:self action:@selector(showSettings)];
  UIBarButtonItem *customIconsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"photo.on.rectangle"] style:UIBarButtonItemStylePlain target:self action:@selector(showCustomIcons)];
  customIconsItem.accessibilityLabel = LMLocalized(@"Custom icons");
  self.navigationItem.leftBarButtonItems = @[settingsItem, customIconsItem];
  UIBarButtonItem *importItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"] style:UIBarButtonItemStylePlain target:self action:@selector(importThemes)];
  importItem.accessibilityLabel = LMLocalized(@"Import themes");
  self.navigationItem.rightBarButtonItems = @[self.editButtonItem, importItem];

  __weak typeof(self) weakSelf = self;
  UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
  configuration.title = LMLocalized(@"Apply");
  configuration.image = [UIImage systemImageNamed:@"square.grid.2x2"];
  configuration.imagePadding = 8;
  configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
  configuration.buttonSize = UIButtonConfigurationSizeLarge;
  configuration.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
  _applyButton = [UIButton buttonWithConfiguration:configuration primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
    [weakSelf apply];
  }]];
  UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
  self.toolbarItems = @[space, [[UIBarButtonItem alloc] initWithCustomView:_applyButton], space];

  self.refreshControl = [UIRefreshControl new];
  [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadThemes) name:UIApplicationWillEnterForegroundNotification object:nil];
  [self reloadThemes];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  // the package manager may still be installing themes in the background
  [_changeTimer invalidate];
  __weak typeof(self) weakSelf = self;
  _changeTimer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
    [weakSelf checkForThemeChanges];
  }];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  [_changeTimer invalidate];
  _changeTimer = nil;
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setToolbarHidden:NO animated:animated];
  [self updateApplyButton];
}

#pragma mark - Data

- (void)reloadThemes {
  [LMThemeLibrary invalidate];
  NSArray *installed = [LMThemeLibrary installedThemes];
  NSMutableArray *active = [NSMutableArray new];
  for (NSString *theme in [LMConfigStore sharedStore].enabledThemes)
    if ([theme isKindOfClass:[NSString class]] && [installed containsObject:theme] && ![active containsObject:theme]) [active addObject:theme];
  _active = active;
  _installed = [installed mutableCopy];
  [_installed removeObjectsInArray:active];
  // keep the previews of themes whose files didn't change, try the ones that couldn't be read again
  for (NSString *theme in _details.allKeys)
    if (![installed containsObject:theme] || _details[theme][@"Error"] || ![_details[theme][@"Stamp"] isEqualToString:LMThemeStamp(theme)]) [_details removeObjectForKey:theme];
  // themes that were uninstalled drop out of the configuration
  if (![active isEqualToArray:[LMConfigStore sharedStore].enabledThemes]) [self saveActiveThemes];

  [self.refreshControl endRefreshing];
  [self.tableView reloadData];
  [self updateEmptyState];
  [self updateApplyButton];
}

// pull to refresh: read every theme again
- (void)refresh {
  [_details removeAllObjects];
  [self reloadThemes];
}

- (void)checkForThemeChanges {
  if (self.tableView.isEditing) return;
  NSMutableSet *known = [NSMutableSet setWithArray:_active];
  [known addObjectsFromArray:_installed];
  if (![[NSSet setWithArray:[LMThemeLibrary installedThemes]] isEqualToSet:known]) {
    [self reloadThemes];
    return;
  }
  // icons added or removed since the preview was made
  for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
    NSString *theme = [self themeAtIndexPath:indexPath];
    NSDictionary *details = theme ? _details[theme] : nil;
    if (!details || [details[@"Stamp"] isEqualToString:LMThemeStamp(theme)]) continue;
    [_details removeObjectForKey:theme];
    [LMThemeLibrary invalidateTheme:theme];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (cell) [self configureCell:cell atIndexPath:indexPath];
  }
}

- (NSString *)themeAtIndexPath:(NSIndexPath *)indexPath {
  NSArray *themes = (indexPath.section == LMThemeSectionActive) ? _active : _installed;
  return (indexPath.row < (NSInteger)themes.count) ? themes[indexPath.row] : nil;
}

- (BOOL)saveActiveThemes {
  [LMConfigStore sharedStore].enabledThemes = _active;
  NSError *error;
  if ([[LMConfigStore sharedStore] save:&error]) {
    [self updateApplyButton];
    return YES;
  }
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:LMLocalized(@"Couldn't save") message:[NSString stringWithFormat:LMLocalized(@"%@\n\nSlippery Board has to be installed as a package (not as an IPA) so it can write its settings."), error.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
  return NO;
}

- (void)loadDetailsForTheme:(NSString *)theme {
  if (!theme || [_loading containsObject:theme]) return;
  [_loading addObject:theme];
  dispatch_async(_detailsQueue, ^{
    NSString *stamp = LMThemeStamp(theme);
    NSDictionary *icons = [LMThemeLibrary iconsInTheme:theme];
    NSMutableArray *paths = [NSMutableArray new];
    for (NSString *bundleID in LMPreviewApps()) {
      NSString *path = icons[bundleID][LMIconLight];
      if (path && paths.count < 4) [paths addObject:path];
    }
    for (NSString *bundleID in [icons.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
      if (paths.count >= 4) break;
      NSString *path = icons[bundleID][LMIconLight];
      if (path && ![paths containsObject:path]) [paths addObject:path];
    }
    NSMutableDictionary *details = [NSMutableDictionary new];
    details[@"Stamp"] = stamp;
    details[@"Count"] = @(icons.count + [LMThemeLibrary iconsByAppNameInTheme:theme].count);
    details[@"Error"] = [LMThemeLibrary readErrorForTheme:theme];
    details[@"Preview"] = LMRenderPreview(paths);
    dispatch_async(dispatch_get_main_queue(), ^{
      [self->_loading removeObject:theme];
      self->_details[theme] = details;
      // update the cell on screen itself, a dequeued cell would be a different one
      for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
        if (![[self themeAtIndexPath:indexPath] isEqualToString:theme]) continue;
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if (cell) [self configureCell:cell atIndexPath:indexPath];
      }
    });
  });
}

#pragma mark - UI state

- (void)updateEmptyState {
  if (_active.count + _installed.count) {
    self.tableView.backgroundView = nil;
    return;
  }
  UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.grid.2x2" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:48 weight:UIImageSymbolWeightLight]]];
  image.tintColor = [UIColor tertiaryLabelColor];
  UILabel *title = [UILabel new];
  title.text = LMLocalized(@"No themes installed");
  title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
  UILabel *detail = [UILabel new];
  detail.text = [NSString stringWithFormat:LMLocalized(@"Install themes from your package manager (they are stored in %@) or import a zip or a .deb with the button at the top."), LMThemesDirectoryDisplayName];
  detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
  detail.textColor = [UIColor secondaryLabelColor];
  detail.numberOfLines = 0;
  detail.textAlignment = NSTextAlignmentCenter;
  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[image, title, detail]];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentCenter;
  stack.spacing = 10;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  UIView *background = [UIView new];
  [background addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.centerYAnchor constraintEqualToAnchor:background.centerYAnchor constant:-40],
    [stack.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:32],
    [stack.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-32],
  ]];
  self.tableView.backgroundView = background;
}

- (void)updateApplyButton {
  UIButtonConfiguration *configuration = _applyButton.configuration;
  configuration.subtitle = [LMConfigStore sharedStore].hasUnappliedChanges ? LMLocalized(@"Changes not applied yet") : nil;
  _applyButton.configuration = configuration;
  [_applyButton sizeToFit];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
  [super setEditing:editing animated:animated];
  [self.tableView setEditing:editing animated:animated];
}

#pragma mark - Actions

- (void)showSettings {
  [self.navigationController pushViewController:[LMSettingsViewController new] animated:YES];
}

- (void)showHelp {
  [self.navigationController pushViewController:[LMHelpViewController new] animated:YES];
}

- (void)showCustomIcons {
  [self.navigationController pushViewController:[LMCustomIconsViewController new] animated:YES];
}

- (void)apply {
  if (![self saveActiveThemes]) return;
  [self presentViewController:[LMApplyViewController new] animated:YES completion:^{
    [self updateApplyButton];
  }];
}

- (void)importThemes {
  // a zip, or a .deb as a package manager would install it
  UTType *debType = [UTType typeWithFilenameExtension:@"deb" conformingToType:UTTypeData];
  UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:debType ? @[UTTypeZIP, debType] : @[UTTypeZIP, UTTypeData] asCopy:YES];
  picker.allowsMultipleSelection = YES;
  picker.delegate = self;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  UIView *view = self.navigationController.view;
  if (!_importSpinner) {
    _importSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _importSpinner.translatesAutoresizingMaskIntoConstraints = NO;
  }
  [view addSubview:_importSpinner];
  [NSLayoutConstraint activateConstraints:@[[_importSpinner.centerXAnchor constraintEqualToAnchor:view.centerXAnchor], [_importSpinner.centerYAnchor constraintEqualToAnchor:view.centerYAnchor]]];
  [_importSpinner startAnimating];
  view.userInteractionEnabled = NO;

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSMutableArray<NSString *> *imported = [NSMutableArray new];
    NSError *failure;
    NSUInteger skipped = 0;
    for (NSURL *url in urls) {
      BOOL scoped = [url startAccessingSecurityScopedResource];
      NSError *error;
      NSArray *names;
      if ([url.pathExtension caseInsensitiveCompare:@"deb"] == NSOrderedSame) {
        NSUInteger skippedInPackage = 0;
        names = [LMDebImporter importThemesFromDebAtPath:url.path skipped:&skippedInPackage error:&error];
        skipped += skippedInPackage;
      } else {
        names = [LMZipImporter importThemesFromZipAtPath:url.path error:&error];
      }
      if (scoped) [url stopAccessingSecurityScopedResource];
      if (names) [imported addObjectsFromArray:names];
      else if (!failure) failure = error;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      [self->_importSpinner stopAnimating];
      [self->_importSpinner removeFromSuperview];
      view.userInteractionEnabled = YES;
      [self reloadThemes];
      NSMutableArray *lines = [NSMutableArray new];
      for (NSString *name in imported) [lines addObject:[LMThemeLibrary displayNameForTheme:name]];
      if (skipped) [lines addObject:[NSString stringWithFormat:LMLocalized(@"%lu themes skipped: they have no IconBundles or Icons folder (sounds, status bar, dock…)."), (unsigned long)skipped]];
      if (failure) [lines addObject:failure.localizedDescription];
      UIAlertController *alert = [UIAlertController alertControllerWithTitle:imported.count ? LMLocalized(@"Themes imported") : LMLocalized(@"Couldn't import") message:[lines componentsJoinedByString:@"\n"] preferredStyle:UIAlertControllerStyleAlert];
      [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
      [self presentViewController:alert animated:YES completion:nil];
    });
  });
}

- (void)setIOSShape:(BOOL)shape forTheme:(NSString *)theme {
  NSMutableArray *themes = [[LMConfigStore sharedStore].shapeThemes mutableCopy];
  if (shape) [themes addObject:theme];
  else [themes removeObject:theme];
  [LMConfigStore sharedStore].shapeThemes = themes;
  [self saveActiveThemes];
  [self.tableView reloadData];
}

- (void)confirmDeleteTheme:(NSString *)theme {
  NSString *name = [LMThemeLibrary displayNameForTheme:theme];
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:LMLocalized(@"Delete theme?") message:[NSString stringWithFormat:LMLocalized(@"%@ is deleted from Slippery Board. You can import it again later."), name] preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
    NSError *error;
    if (![[NSFileManager defaultManager] removeItemAtPath:[LMThemeLibrary directoryForTheme:theme] error:&error]) {
      UIAlertController *failed = [UIAlertController alertControllerWithTitle:LMLocalized(@"Couldn't delete") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
      [failed addAction:[UIAlertAction actionWithTitle:LMLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
      [self presentViewController:failed animated:YES completion:nil];
      return;
    }
    [LMThemeLibrary invalidateTheme:theme];
    NSMutableArray *shapeThemes = [[LMConfigStore sharedStore].shapeThemes mutableCopy];
    [shapeThemes removeObject:theme];
    [LMConfigStore sharedStore].shapeThemes = shapeThemes;
    [self reloadThemes]; // it is not installed anymore, so it drops out of the active themes and the config is saved
    [self saveActiveThemes];
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return (_active.count + _installed.count) ? 2 : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return (section == LMThemeSectionActive) ? _active.count : _installed.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
  return (section == LMThemeSectionActive) ? LMLocalized(@"Active") : LMLocalized(@"Installed");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
  if (section == LMThemeSectionActive)
    return _active.count ? [NSString stringWithFormat:@"%@ %@", LMLocalized(@"When several themes have an icon for the same app, the one higher up wins. Tap Edit to change the order."), LMLocalized(@"Swipe right on an active theme to give all its icons the icon shape of the settings.")] : LMLocalized(@"Tap a theme below to activate it.");
  return _installed.count ? nil : LMLocalized(@"All installed themes are active.");
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
  NSString *theme = [self themeAtIndexPath:indexPath];
  NSDictionary *details = theme ? _details[theme] : nil;
  if (!details) [self loadDetailsForTheme:theme];

  UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
  content.text = theme ? [LMThemeLibrary displayNameForTheme:theme] : nil;
  content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
  if (details[@"Error"]) content.secondaryText = LMLocalized(@"Couldn't read this theme, pull down to try again");
  else if (details) content.secondaryText = [NSString localizedStringWithFormat:LMLocalized(@"%lu icons"), (unsigned long)[details[@"Count"] unsignedIntegerValue]];
  else content.secondaryText = LMLocalized(@"Loading…");
  if (theme && [[LMConfigStore sharedStore].shapeThemes containsObject:theme] && !details[@"Error"])
    content.secondaryText = [NSString stringWithFormat:@"%@ · %@", content.secondaryText, LMLocalized(@"iOS shape")];
  content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
  content.image = details[@"Preview"] ? : [UIImage systemImageNamed:@"square.grid.2x2"];
  content.imageProperties.maximumSize = CGSizeMake(44, 44);
  content.imageProperties.reservedLayoutSize = CGSizeMake(44, 44);
  content.imageProperties.tintColor = [UIColor tertiaryLabelColor];
  cell.contentConfiguration = content;
  cell.accessoryType = (indexPath.section == LMThemeSectionActive) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
  cell.showsReorderControl = YES;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Theme" forIndexPath:indexPath];
  [self configureCell:cell atIndexPath:indexPath];
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  NSString *theme = [self themeAtIndexPath:indexPath];
  if (!theme) return;
  NSIndexPath *destination;
  if (indexPath.section == LMThemeSectionActive) {
    [_active removeObjectAtIndex:indexPath.row];
    NSUInteger position = [_installed indexOfObject:theme inSortedRange:NSMakeRange(0, _installed.count) options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(NSString *a, NSString *b) {
      return [[LMThemeLibrary displayNameForTheme:a] localizedCaseInsensitiveCompare:[LMThemeLibrary displayNameForTheme:b]];
    }];
    [_installed insertObject:theme atIndex:position];
    destination = [NSIndexPath indexPathForRow:position inSection:LMThemeSectionInstalled];
  } else {
    [_installed removeObjectAtIndex:indexPath.row];
    [_active addObject:theme];
    destination = [NSIndexPath indexPathForRow:_active.count - 1 inSection:LMThemeSectionActive];
  }
  [tableView performBatchUpdates:^{
    [tableView moveRowAtIndexPath:indexPath toIndexPath:destination];
  } completion:^(BOOL finished) {
    [tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationNone];
  }];
  [self saveActiveThemes];
}

// swipe right: give the icons of an active theme the iOS shape
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSString *theme = [self themeAtIndexPath:indexPath];
  if (!theme || indexPath.section != LMThemeSectionActive) return nil;
  BOOL shape = [[LMConfigStore sharedStore].shapeThemes containsObject:theme];
  UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:shape ? LMLocalized(@"Own shape") : LMLocalized(@"iOS shape") handler:^(UIContextualAction *contextualAction, UIView *sourceView, void (^completion)(BOOL)) {
    [self setIOSShape:!shape forTheme:theme];
    completion(YES);
  }];
  action.image = [UIImage systemImageNamed:shape ? @"square" : @"app"];
  action.backgroundColor = [UIColor systemIndigoColor];
  return [UISwipeActionsConfiguration configurationWithActions:@[action]];
}

// swipe left: delete a theme that was imported in the app, the others belong to the package manager
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSString *theme = [self themeAtIndexPath:indexPath];
  if (!theme || ![LMThemeLibrary isImportedTheme:theme]) return nil;
  UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:LMLocalized(@"Delete") handler:^(UIContextualAction *contextualAction, UIView *sourceView, void (^completion)(BOOL)) {
    [self confirmDeleteTheme:theme];
    completion(NO);
  }];
  action.image = [UIImage systemImageNamed:@"trash"];
  return [UISwipeActionsConfiguration configurationWithActions:@[action]];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
  return indexPath.section == LMThemeSectionActive;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)proposed {
  if (proposed.section == LMThemeSectionActive) return proposed;
  return [NSIndexPath indexPathForRow:(_active.count ? _active.count - 1 : 0) inSection:LMThemeSectionActive];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
  NSString *theme = _active[source.row];
  [_active removeObjectAtIndex:source.row];
  [_active insertObject:theme atIndex:destination.row];
  [self saveActiveThemes];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
  return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
  return NO;
}

@end
