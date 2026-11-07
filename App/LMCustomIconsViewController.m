#import "LMCustomIconsViewController.h"
#import "LMAppPickerViewController.h"
#import "LMApplyViewController.h"
#import "LMCustomIconStore.h"
#import "LMConfigStore.h"
#import "../Shared/LMThemeLibrary.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef NS_ENUM(NSInteger, LMIconSection) {
  LMIconSectionCustom,
  LMIconSectionIOSShape,
};

// the button at the top shows every icon with the iOS shape and the background of the settings, to see what it would look like (default: icons as they are)
static BOOL LMPreviewShape = NO;

@interface LMCustomIconsViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
@end

@implementation LMCustomIconsViewController {
  NSMutableArray<NSString *> *_custom; // lowercased bundle ids with a custom icon that keeps its own shape
  NSMutableArray<NSString *> *_shape;  // lowercased bundle ids that get the iOS shape
  NSDictionary<NSString *, LMAppInfo *> *_apps; // lowercased bundle id -> app, nil until loaded
  NSDictionary<NSString *, NSDictionary *> *_themeIcons; // what the active themes give, for the apps without a custom icon
  NSString *_pendingBundleID; // the app an image is being picked for
  UIBarButtonItem *_addItem;
  UIBarButtonItem *_shapeItem;
  UIButton *_applyButton;
}

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = LMLocalized(@"Custom icons");
  self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
  _addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addApp)];
  _shapeItem = [[UIBarButtonItem alloc] initWithImage:nil style:UIBarButtonItemStylePlain target:self action:@selector(toggleShape)];
  _shapeItem.accessibilityLabel = LMLocalized(@"Preview the iOS shape");
  [self updateShapeItem];
  self.navigationItem.rightBarButtonItems = @[_addItem, _shapeItem];
  [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Icon"];
  self.tableView.rowHeight = 64;

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

  // app names, to show something nicer than bundle ids
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSMutableDictionary *apps = [NSMutableDictionary new];
    for (LMAppInfo *app in [LMAppCatalog installedApps]) apps[app.bundleID.lowercaseString] = app;
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) strongSelf = weakSelf;
      if (!strongSelf) return;
      strongSelf->_apps = apps;
      [strongSelf reload];
    });
  });
  [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setToolbarHidden:NO animated:animated];
  [self updateApplyButton];
}

#pragma mark - Data

- (NSString *)nameForBundleID:(NSString *)bundleID {
  return _apps[bundleID].name ? : bundleID;
}

- (void)reload {
  LMConfigStore *config = [LMConfigStore sharedStore];
  NSSet *shaped = [NSSet setWithArray:config.shapeApps];
  NSMutableArray *custom = [NSMutableArray new];
  for (NSString *bundleID in [LMCustomIconStore bundleIDs]) if (![shaped containsObject:bundleID]) [custom addObject:bundleID];
  NSMutableArray *shape = [config.shapeApps mutableCopy];
  NSComparisonResult (^byName)(NSString *, NSString *) = ^NSComparisonResult(NSString *a, NSString *b) {
    return [[self nameForBundleID:a] localizedCaseInsensitiveCompare:[self nameForBundleID:b]];
  };
  [custom sortUsingComparator:byName];
  [shape sortUsingComparator:byName];
  _custom = custom;
  _shape = shape;
  // the icons of the active themes, for the apps in the iOS shape section that have no custom icon
  _themeIcons = _shape.count ? [LMThemeLibrary resolvedIconsForThemes:config.enabledThemes appNames:nil] : @{};
  [self.tableView reloadData];
  [self updateEmptyState];
  [self updateApplyButton];
}

- (NSMutableArray<NSString *> *)listForSection:(NSInteger)section {
  return section == LMIconSectionCustom ? _custom : _shape;
}

- (BOOL)hasIOSShape:(NSString *)bundleID {
  return [[LMConfigStore sharedStore].shapeApps containsObject:bundleID.lowercaseString];
}

// saves the config, shows what went wrong
- (BOOL)saveConfig {
  NSError *error;
  if ([[LMConfigStore sharedStore] save:&error]) return YES;
  [self showError:error];
  return NO;
}

- (void)setIOSShape:(BOOL)shape forBundleID:(NSString *)bundleID {
  NSMutableArray *apps = [[LMConfigStore sharedStore].shapeApps mutableCopy];
  if (shape) [apps addObject:bundleID.lowercaseString];
  else [apps removeObject:bundleID.lowercaseString];
  [LMConfigStore sharedStore].shapeApps = apps;
  [self saveConfig];
  [self reload];
}

- (void)updateEmptyState {
  if (_custom.count + _shape.count) {
    self.tableView.backgroundView = nil;
    return;
  }
  UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"photo.on.rectangle" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:48 weight:UIImageSymbolWeightLight]]];
  image.tintColor = [UIColor tertiaryLabelColor];
  UILabel *title = [UILabel new];
  title.text = LMLocalized(@"No custom icons");
  title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
  UILabel *detail = [UILabel new];
  detail.text = LMLocalized(@"Tap + to pick an app, then an image for its icon.");
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

- (void)updateShapeItem {
  _shapeItem.image = [UIImage systemImageNamed:LMPreviewShape ? @"app.fill" : @"app"];
}

- (void)showError:(NSError *)error {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:LMLocalized(@"Couldn't save") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)apply {
  [self presentViewController:[LMApplyViewController new] animated:YES completion:^{
    [self updateApplyButton];
  }];
}

- (void)toggleShape {
  LMPreviewShape = !LMPreviewShape;
  [self updateShapeItem];
  [self.tableView reloadData];
}

- (void)addApp {
  __weak typeof(self) weakSelf = self;
  NSMutableSet *listed = [NSMutableSet setWithArray:[LMCustomIconStore bundleIDs]];
  [listed addObjectsFromArray:[LMConfigStore sharedStore].shapeApps];
  LMAppPickerViewController *picker = [[LMAppPickerViewController alloc] initWithCustomizedBundleIDs:listed pick:^(LMAppInfo *app) {
    [weakSelf chooseImageSourceForBundleID:app.bundleID name:app.name sourceView:nil];
  }];
  [self presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
}

// sourceView: where the sheet comes from on iPad, nil for the + button
- (void)chooseImageSourceForBundleID:(NSString *)bundleID name:(NSString *)name sourceView:(UIView *)sourceView {
  UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  __weak typeof(self) weakSelf = self;
  [sheet addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Choose from Photos") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    [weakSelf pickFromPhotosForBundleID:bundleID];
  }]];
  [sheet addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Choose from Files") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    [weakSelf pickFromFilesForBundleID:bundleID];
  }]];
  BOOL shape = [self hasIOSShape:bundleID];
  [sheet addAction:[UIAlertAction actionWithTitle:shape ? LMLocalized(@"Own shape") : LMLocalized(@"iOS shape") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    [weakSelf setIOSShape:!shape forBundleID:bundleID];
  }]];
  if ([LMCustomIconStore hasIconForBundleID:bundleID]) {
    [sheet addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Remove custom icon") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
      [weakSelf removeBundleID:bundleID];
    }]];
  }
  [sheet addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
  UIPopoverPresentationController *popover = sheet.popoverPresentationController;
  if (sourceView) {
    popover.sourceView = sourceView;
    popover.sourceRect = sourceView.bounds;
  } else {
    popover.barButtonItem = _addItem;
  }
  [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pickFromPhotosForBundleID:(NSString *)bundleID {
  _pendingBundleID = bundleID;
  UIImagePickerController *picker = [UIImagePickerController new];
  picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
  picker.allowsEditing = YES; // square crop
  picker.delegate = self;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)pickFromFilesForBundleID:(NSString *)bundleID {
  _pendingBundleID = bundleID;
  UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
  picker.allowsMultipleSelection = NO;
  picker.delegate = self;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)useImage:(UIImage *)image {
  NSString *bundleID = _pendingBundleID;
  _pendingBundleID = nil;
  if (!bundleID) return;
  NSError *error;
  if (!image) {
    error = [NSError errorWithDomain:@"LumenBoard" code:2 userInfo:@{ NSLocalizedDescriptionKey : LMLocalized(@"This image can't be used as an icon.") }];
    [self showError:error];
    return;
  }
  if (![LMCustomIconStore setImage:image forBundleID:bundleID error:&error]) {
    [self showError:error];
    return;
  }
  [self reload];
}

- (void)removeBundleID:(NSString *)bundleID {
  NSError *error;
  if (![LMCustomIconStore removeIconForBundleID:bundleID error:&error]) {
    [self showError:error];
    return;
  }
  [self reload];
}

#pragma mark - Pickers

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
  UIImage *image = info[UIImagePickerControllerEditedImage] ? : info[UIImagePickerControllerOriginalImage];
  [picker dismissViewControllerAnimated:YES completion:^{
    [self useImage:image];
  }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
  _pendingBundleID = nil;
  [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  NSURL *url = urls.firstObject;
  BOOL scoped = [url startAccessingSecurityScopedResource];
  UIImage *image = url ? [UIImage imageWithData:[NSData dataWithContentsOfURL:url]] : nil;
  if (scoped) [url stopAccessingSecurityScopedResource];
  // the picker is still closing
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self useImage:image];
  });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
  _pendingBundleID = nil;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return [self listForSection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
  if (![self listForSection:section].count) return nil;
  return section == LMIconSectionCustom ? LMLocalized(@"Custom icons") : LMLocalized(@"iOS shape");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
  if (![self listForSection:section].count) return nil;
  if (section == LMIconSectionCustom) return LMLocalized(@"A custom icon replaces the icon of that app, whatever your themes say. Swipe right on an icon to give it the iOS shape. Tap Apply afterwards.");
  return LMLocalized(@"These icons get the iOS icon shape when the icon shape in Settings is \"Theme's own shape\". Swipe right to give them their own shape back.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Icon" forIndexPath:indexPath];
  NSString *bundleID = [self listForSection:indexPath.section][indexPath.row];
  UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
  content.text = [self nameForBundleID:bundleID];
  content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
  BOOL missing = _apps && !_apps[bundleID];
  content.secondaryText = missing ? [NSString stringWithFormat:@"%@ · %@", bundleID, LMLocalized(@"App not installed")] : bundleID;
  content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
  content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];

  // the custom icon, else what the themes give, else the icon as it is on the home screen
  UIImage *thumbnail = [LMCustomIconStore thumbnailForBundleID:bundleID pixels:144];
  if (!thumbnail) thumbnail = [LMCustomIconStore thumbnailForPath:_themeIcons[bundleID][LMIconLight] pixels:144];
  if (!thumbnail) thumbnail = [LMAppCatalog iconForBundleID:_apps[bundleID].bundleID ? : bundleID];
  // The icons that get the iOS shape are shown with it. With the preview button on, every icon is shown with the iOS shape
  // and the background of the settings (the light or the dark one, like the current mode).
  if (thumbnail && LMPreviewShape) {
    LMConfigStore *config = [LMConfigStore sharedStore];
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    thumbnail = [LMCustomIconStore image:thumbnail overBackground:dark ? config.backgroundDark : config.backgroundLight];
  }
  BOOL shaped = thumbnail && (indexPath.section == LMIconSectionIOSShape || LMPreviewShape);
  content.image = thumbnail ? (shaped ? [LMCustomIconStore squircleImage:thumbnail] : thumbnail) : [UIImage systemImageNamed:@"photo"];
  content.imageProperties.maximumSize = CGSizeMake(48, 48);
  content.imageProperties.reservedLayoutSize = CGSizeMake(48, 48);
  content.imageProperties.cornerRadius = 0;
  content.imageProperties.tintColor = [UIColor tertiaryLabelColor];
  cell.contentConfiguration = content;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  NSString *bundleID = [self listForSection:indexPath.section][indexPath.row];
  [self chooseImageSourceForBundleID:bundleID name:[self nameForBundleID:bundleID] sourceView:[tableView cellForRowAtIndexPath:indexPath]];
}

// swipe right: to the iOS shape section and back
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSString *bundleID = [self listForSection:indexPath.section][indexPath.row];
  BOOL shape = indexPath.section == LMIconSectionIOSShape;
  UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:shape ? LMLocalized(@"Own shape") : LMLocalized(@"iOS shape") handler:^(UIContextualAction *contextualAction, UIView *sourceView, void (^completion)(BOOL)) {
    [self setIOSShape:!shape forBundleID:bundleID];
    completion(YES);
  }];
  action.image = [UIImage systemImageNamed:shape ? @"square" : @"app"];
  action.backgroundColor = [UIColor systemIndigoColor];
  return [UISwipeActionsConfiguration configurationWithActions:@[action]];
}

// swipe left: remove the custom icon
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSString *bundleID = [self listForSection:indexPath.section][indexPath.row];
  if (![LMCustomIconStore hasIconForBundleID:bundleID]) return nil;
  UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:LMLocalized(@"Remove") handler:^(UIContextualAction *contextualAction, UIView *sourceView, void (^completion)(BOOL)) {
    [self removeBundleID:bundleID];
    completion(YES);
  }];
  action.image = [UIImage systemImageNamed:@"trash"];
  return [UISwipeActionsConfiguration configurationWithActions:@[action]];
}

@end
