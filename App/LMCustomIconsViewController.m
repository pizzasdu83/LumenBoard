#import "LMCustomIconsViewController.h"
#import "LMAppPickerViewController.h"
#import "LMApplyViewController.h"
#import "LMCustomIconStore.h"
#import "LMConfigStore.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface LMCustomIconsViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
@end

@implementation LMCustomIconsViewController {
  NSMutableArray<NSString *> *_bundleIDs; // lowercased, sorted by app name
  NSDictionary<NSString *, LMAppInfo *> *_apps; // lowercased bundle id -> app, nil until loaded
  NSString *_pendingBundleID; // the app an image is being picked for
  UIButton *_applyButton;
}

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = LMLocalized(@"Custom icons");
  self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addApp)];
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
  NSMutableArray *bundleIDs = [[LMCustomIconStore bundleIDs] mutableCopy];
  [bundleIDs sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
    return [[self nameForBundleID:a] localizedCaseInsensitiveCompare:[self nameForBundleID:b]];
  }];
  _bundleIDs = bundleIDs;
  [self.tableView reloadData];
  [self updateEmptyState];
  [self updateApplyButton];
}

- (void)updateEmptyState {
  if (_bundleIDs.count) {
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

- (void)showError:(NSError *)error {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:LMLocalized(@"Couldn't save") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)apply {
  [self presentViewController:[[LMApplyViewController alloc] initWithClearingIconCache:NO] animated:YES completion:^{
    [self updateApplyButton];
  }];
}

- (void)addApp {
  __weak typeof(self) weakSelf = self;
  NSSet *customized = [NSSet setWithArray:[LMCustomIconStore bundleIDs]];
  LMAppPickerViewController *picker = [[LMAppPickerViewController alloc] initWithCustomizedBundleIDs:customized pick:^(LMAppInfo *app) {
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
    popover.barButtonItem = self.navigationItem.rightBarButtonItem;
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
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return _bundleIDs.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
  return LMLocalized(@"A custom icon replaces the icon of that app, whatever your themes say. Tap Apply afterwards.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Icon" forIndexPath:indexPath];
  NSString *bundleID = _bundleIDs[indexPath.row];
  UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
  content.text = [self nameForBundleID:bundleID];
  content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
  BOOL missing = _apps && !_apps[bundleID];
  content.secondaryText = missing ? [NSString stringWithFormat:@"%@ · %@", bundleID, LMLocalized(@"App not installed")] : bundleID;
  content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
  content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
  content.image = [LMCustomIconStore thumbnailForBundleID:bundleID pixels:144] ? : [UIImage systemImageNamed:@"photo"];
  content.imageProperties.maximumSize = CGSizeMake(48, 48);
  content.imageProperties.reservedLayoutSize = CGSizeMake(48, 48);
  content.imageProperties.cornerRadius = 10.8;
  content.imageProperties.tintColor = [UIColor tertiaryLabelColor];
  cell.contentConfiguration = content;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  NSString *bundleID = _bundleIDs[indexPath.row];
  [self chooseImageSourceForBundleID:bundleID name:[self nameForBundleID:bundleID] sourceView:[tableView cellForRowAtIndexPath:indexPath]];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
  if (editingStyle != UITableViewCellEditingStyleDelete) return;
  [self removeBundleID:_bundleIDs[indexPath.row]];
}

@end
