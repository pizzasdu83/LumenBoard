#import "LMBackgroundViewController.h"
#import "LMConfigStore.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <sys/stat.h>

typedef NS_ENUM(NSInteger, LMBackgroundSection) {
  LMBackgroundSectionPreview,
  LMBackgroundSectionMode,
  LMBackgroundSectionOptions,
  LMBackgroundSectionCount,
};

static NSArray<NSString *> *LMModes(void) {
  return @[@"none", @"color", @"gradient", @"image"];
}

static NSString *LMHexFromColor(UIColor *color) {
  CGFloat red = 0, green = 0, blue = 0, alpha = 0;
  [color getRed:&red green:&green blue:&blue alpha:&alpha];
  return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(red * 255), (int)lround(green * 255), (int)lround(blue * 255)];
}

static UIColor *LMColorFromHex(id hex) {
  if (![hex isKindOfClass:[NSString class]]) return nil;
  NSString *digits = [hex hasPrefix:@"#"] ? [hex substringFromIndex:1] : hex;
  unsigned long long value = 0;
  if ((digits.length != 6 && digits.length != 8) || ![[NSScanner scannerWithString:digits] scanHexLongLong:&value]) return nil;
  if (digits.length == 6) value = (value << 8) | 0xFF;
  return [UIColor colorWithRed:((value >> 24) & 0xFF) / 255.0 green:((value >> 16) & 0xFF) / 255.0 blue:((value >> 8) & 0xFF) / 255.0 alpha:(value & 0xFF) / 255.0];
}

// the image goes into LMBackgroundsDirectory, scaled to at most 1024 px (it is drawn behind icons that are 512 px at most)
static NSString *LMSaveBackgroundImage(UIImage *image, BOOL dark, NSError **error) {
  CGSize pixels = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
  CGFloat longest = MAX(pixels.width, pixels.height);
  if (longest <= 0) return nil;
  CGFloat factor = MIN(1.0, 1024.0 / longest);
  CGSize size = CGSizeMake(MAX(1, round(pixels.width * factor)), MAX(1, round(pixels.height * factor)));
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
  format.scale = 1;
  format.opaque = NO;
  UIImage *scaled = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
  }];
  NSData *data = UIImagePNGRepresentation(scaled);
  if (!data) {
    if (error) *error = [NSError errorWithDomain:@"LumenBoard" code:5 userInfo:@{ NSLocalizedDescriptionKey : LMLocalized(@"This image can't be used.") }];
    return nil;
  }
  NSString *directory = LMBackgroundsDirectory;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
  // a new name every time, so SpringBoard and iconservicesagent never keep an old picture
  NSString *file = [NSString stringWithFormat:@"%@-%@.png", dark ? @"dark" : @"light", [NSUUID UUID].UUIDString];
  NSString *path = [directory stringByAppendingPathComponent:file];
  if (![data writeToFile:path options:NSDataWritingAtomic error:error]) return nil;
  chmod(directory.fileSystemRepresentation, 0755);
  chmod(path.fileSystemRepresentation, 0644);
  return file;
}

#pragma mark - Preview

// a home screen icon with the background and a sample glyph on top of it
@interface LMBackgroundPreview : UIView
- (void)showBackground:(NSDictionary *)background picture:(UIImage *)picture;
@end

@implementation LMBackgroundPreview {
  CAGradientLayer *_gradient;
  UIImageView *_picture;
  UIImageView *_glyph;
}

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
    _gradient = [CAGradientLayer layer];
    _gradient.hidden = YES;
    [self.layer addSublayer:_gradient];
    _picture = [UIImageView new];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    [self addSubview:_picture];
    _glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"star.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:48 weight:UIImageSymbolWeightSemibold]]];
    _glyph.contentMode = UIViewContentModeCenter;
    _glyph.layer.shadowColor = [UIColor blackColor].CGColor;
    _glyph.layer.shadowOpacity = 0.3;
    _glyph.layer.shadowRadius = 4;
    _glyph.layer.shadowOffset = CGSizeMake(0, 2);
    [self addSubview:_glyph];
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  _gradient.frame = self.bounds;
  _picture.frame = self.bounds;
  _glyph.frame = self.bounds;
  self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.2237; // the iOS icon shape
}

- (void)showBackground:(NSDictionary *)background picture:(UIImage *)picture {
  NSString *mode = background[@"Mode"];
  self.backgroundColor = [UIColor tertiarySystemFillColor];
  _glyph.tintColor = [UIColor secondaryLabelColor];
  _gradient.hidden = YES;
  _picture.image = nil;
  if ([mode isEqualToString:@"color"] && LMColorFromHex(background[@"Color"])) {
    self.backgroundColor = LMColorFromHex(background[@"Color"]);
    _glyph.tintColor = [UIColor whiteColor];
  } else if ([mode isEqualToString:@"gradient"] && LMColorFromHex(background[@"Color"]) && LMColorFromHex(background[@"Color2"])) {
    _gradient.colors = @[(id)LMColorFromHex(background[@"Color"]).CGColor, (id)LMColorFromHex(background[@"Color2"]).CGColor];
    // same direction as the icons: 0 degrees left to right, 90 top to bottom, long enough to reach the corners
    double angle = [background[@"Angle"] doubleValue] * M_PI / 180.0, dx = cos(angle), dy = sin(angle), half = (fabs(dx) + fabs(dy)) / 2;
    _gradient.startPoint = CGPointMake(0.5 - dx * half, 0.5 - dy * half);
    _gradient.endPoint = CGPointMake(0.5 + dx * half, 0.5 + dy * half);
    _gradient.hidden = NO;
    _glyph.tintColor = [UIColor whiteColor];
  } else if ([mode isEqualToString:@"image"] && picture) {
    _picture.image = picture;
    _glyph.tintColor = [UIColor whiteColor];
  }
}

@end

#pragma mark - Screen

@interface LMBackgroundViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
@end

@implementation LMBackgroundViewController {
  BOOL _dark;
  NSMutableDictionary *_background;
  LMBackgroundPreview *_preview;
}

- (instancetype)initWithDark:(BOOL)dark {
  if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
    _dark = dark;
    NSDictionary *saved = dark ? [LMConfigStore sharedStore].backgroundDark : [LMConfigStore sharedStore].backgroundLight;
    _background = [saved mutableCopy] ? : [NSMutableDictionary new];
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = _dark ? LMLocalized(@"Dark mode") : LMLocalized(@"Light mode");
  self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
  _preview = [[LMBackgroundPreview alloc] initWithFrame:CGRectMake(0, 0, 120, 120)];
  [self updatePreview];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setToolbarHidden:YES animated:animated];
}

#pragma mark - Data

- (NSInteger)modeIndex {
  NSInteger index = [LMModes() indexOfObject:_background[@"Mode"] ? : @"none"];
  return index == NSNotFound ? 0 : index;
}

- (NSString *)imagePath {
  NSString *file = _background[@"Image"];
  return ([file isKindOfClass:[NSString class]] && file.length && ![file containsString:@"/"]) ? [LMBackgroundsDirectory stringByAppendingPathComponent:file] : nil;
}

- (void)updatePreview {
  NSString *path = [self imagePath];
  [_preview showBackground:_background picture:path ? [UIImage imageWithContentsOfFile:path] : nil];
}

// what each mode starts with, so there is always something to see
- (void)fillDefaults {
  if (!_background[@"Color"]) _background[@"Color"] = _dark ? @"#1C1C1E" : @"#FFFFFF";
  if (!_background[@"Color2"]) _background[@"Color2"] = _dark ? @"#000000" : @"#C7C7CC";
  if (!_background[@"Angle"]) _background[@"Angle"] = @90;
}

- (void)save {
  LMConfigStore *config = [LMConfigStore sharedStore];
  if (_dark) config.backgroundDark = _background;
  else config.backgroundLight = _background;
  NSError *error;
  if (![config save:&error]) [self showError:error];
  [self updatePreview];
}

- (void)showError:(NSError *)error {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:LMLocalized(@"Couldn't save") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)modeChanged:(UISegmentedControl *)control {
  _background[@"Mode"] = LMModes()[control.selectedSegmentIndex];
  [self fillDefaults];
  [self save];
  [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:LMBackgroundSectionOptions] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)colorChanged:(UIColorWell *)well {
  _background[well.tag == 0 ? @"Color" : @"Color2"] = LMHexFromColor(well.selectedColor);
  [self save];
}

- (void)angleChanged:(UISlider *)slider {
  _background[@"Angle"] = @((int)lround(slider.value));
  UILabel *label = (UILabel *)[slider.superview viewWithTag:1];
  label.text = [NSString stringWithFormat:@"%d°", (int)lround(slider.value)];
  [self save];
}

- (void)chooseImage {
  UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  __weak typeof(self) weakSelf = self;
  [sheet addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Choose from Photos") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = weakSelf;
    [weakSelf presentViewController:picker animated:YES completion:nil];
  }]];
  [sheet addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Choose from Files") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    picker.allowsMultipleSelection = NO;
    picker.delegate = weakSelf;
    [weakSelf presentViewController:picker animated:YES completion:nil];
  }]];
  [sheet addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
  UIView *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:LMBackgroundSectionOptions]];
  sheet.popoverPresentationController.sourceView = cell ? : self.view;
  sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
  [self presentViewController:sheet animated:YES completion:nil];
}

- (void)removeImage {
  NSString *path = [self imagePath];
  if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
  [_background removeObjectForKey:@"Image"];
  [self save];
  [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:LMBackgroundSectionOptions] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)useImage:(UIImage *)image {
  NSError *error;
  NSString *file = image ? LMSaveBackgroundImage(image, _dark, &error) : nil;
  if (!file) {
    [self showError:error ? : [NSError errorWithDomain:@"LumenBoard" code:5 userInfo:@{ NSLocalizedDescriptionKey : LMLocalized(@"This image can't be used.") }]];
    return;
  }
  NSString *previous = [self imagePath];
  if (previous) [[NSFileManager defaultManager] removeItemAtPath:previous error:nil];
  _background[@"Image"] = file;
  _background[@"Mode"] = @"image";
  [self save];
  [self.tableView reloadData];
}

#pragma mark - Pickers

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
  UIImage *image = info[UIImagePickerControllerOriginalImage];
  [picker dismissViewControllerAnimated:YES completion:^{
    [self useImage:image];
  }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
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

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return LMBackgroundSectionCount;
}

- (NSInteger)optionRowCount {
  switch ([self modeIndex]) {
    case 1: return 1; // color
    case 2: return 3; // start, end, angle
    case 3: return [self imagePath] ? 2 : 1; // choose, remove
    default: return 0;
  }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  switch (section) {
    case LMBackgroundSectionPreview: return 1;
    case LMBackgroundSectionMode: return 1;
    default: return [self optionRowCount];
  }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
  if (section != LMBackgroundSectionMode) return nil;
  return LMLocalized(@"The background only goes behind icons that have the iOS shape, and shows where the icon is transparent. Swipe right on an icon or a theme to give it that shape. Tap Apply afterwards.");
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
  return indexPath.section == LMBackgroundSectionPreview ? 160 : UITableViewAutomaticDimension;
}

- (UIColorWell *)colorWellWithKey:(NSString *)key tag:(NSInteger)tag {
  UIColorWell *well = [UIColorWell new];
  well.supportsAlpha = NO;
  well.selectedColor = LMColorFromHex(_background[key]) ? : [UIColor whiteColor];
  well.tag = tag;
  well.frame = CGRectMake(0, 0, 34, 34); // an accessory view needs a size
  [well addTarget:self action:@selector(colorChanged:) forControlEvents:UIControlEventValueChanged];
  return well;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
  cell.selectionStyle = UITableViewCellSelectionStyleNone;

  if (indexPath.section == LMBackgroundSectionPreview) {
    _preview.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:_preview];
    [NSLayoutConstraint activateConstraints:@[
      [_preview.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
      [_preview.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
      [_preview.widthAnchor constraintEqualToConstant:120],
      [_preview.heightAnchor constraintEqualToConstant:120],
    ]];
    return cell;
  }

  if (indexPath.section == LMBackgroundSectionMode) {
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:@[LMLocalized(@"None"), LMLocalized(@"Color"), LMLocalized(@"Gradient"), LMLocalized(@"Image")]];
    control.selectedSegmentIndex = [self modeIndex];
    [control addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:control];
    [NSLayoutConstraint activateConstraints:@[
      [control.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
      [control.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
      [control.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
      [control.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
    ]];
    return cell;
  }

  UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
  NSInteger mode = [self modeIndex];
  if (mode == 1) {
    content.text = LMLocalized(@"Color");
    cell.accessoryView = [self colorWellWithKey:@"Color" tag:0];
  } else if (mode == 2 && indexPath.row < 2) {
    content.text = indexPath.row == 0 ? LMLocalized(@"Start color") : LMLocalized(@"End color");
    cell.accessoryView = [self colorWellWithKey:indexPath.row == 0 ? @"Color" : @"Color2" tag:indexPath.row];
  } else if (mode == 2) {
    // angle: a label and a slider
    UILabel *title = [UILabel new];
    title.text = LMLocalized(@"Angle");
    UILabel *value = [UILabel new];
    value.tag = 1;
    value.textColor = [UIColor secondaryLabelColor];
    value.text = [NSString stringWithFormat:@"%d°", [_background[@"Angle"] intValue]];
    UISlider *slider = [UISlider new];
    slider.minimumValue = 0;
    slider.maximumValue = 360;
    slider.value = [_background[@"Angle"] floatValue];
    [slider addTarget:self action:@selector(angleChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[title, value]];
    top.distribution = UIStackViewDistributionEqualSpacing;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[top, slider]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *holder = [UIView new];
    holder.translatesAutoresizingMaskIntoConstraints = NO;
    [holder addSubview:stack];
    [cell.contentView addSubview:holder];
    [NSLayoutConstraint activateConstraints:@[
      [holder.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
      [holder.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
      [holder.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
      [holder.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
      [stack.topAnchor constraintEqualToAnchor:holder.topAnchor],
      [stack.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
      [stack.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor],
      [stack.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor],
    ]];
    return cell;
  } else if (indexPath.row == 0) {
    content.text = LMLocalized(@"Choose image");
    content.textProperties.color = self.view.tintColor;
    content.image = [UIImage systemImageNamed:@"photo"];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else {
    content.text = LMLocalized(@"Remove image");
    content.textProperties.color = [UIColor systemRedColor];
    content.image = [UIImage systemImageNamed:@"trash"];
    content.imageProperties.tintColor = [UIColor systemRedColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  }
  cell.contentConfiguration = content;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if (indexPath.section != LMBackgroundSectionOptions || [self modeIndex] != 3) return;
  if (indexPath.row == 0) [self chooseImage];
  else [self removeImage];
}

@end
