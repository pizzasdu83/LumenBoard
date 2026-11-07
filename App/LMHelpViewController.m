#import "LMHelpViewController.h"

@implementation LMHelpViewController {
  NSArray<NSArray<NSString *> *> *_topics; // title, text
}

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = LMLocalized(@"How does this work?");
  self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
  self.tableView.allowsSelection = NO;
  [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Topic"];
  _topics = @[
    @[LMLocalized(@"Themes"), LMLocalized(@"Install icon themes with your package manager, or import a zip or a .deb with the button at the top right. Tap a theme to turn it on. When several active themes have an icon for the same app, the one higher up wins: tap Edit to change the order.")],
    @[LMLocalized(@"Apply"), LMLocalized(@"Nothing changes on your home screen until you tap Apply. It draws the icons of your active themes and your custom icons. If an icon still looks wrong afterwards, use Rebuild icons in Settings.")],
    @[LMLocalized(@"Custom icons"), LMLocalized(@"The photo button at the top left lets you pick an image for a single app, from Photos or Files. A custom icon wins over every theme.")],
    @[LMLocalized(@"Icon shape"), LMLocalized(@"In Settings, the icon shape (iOS shape, circle, rounded square, square, teardrop or the shape of a theme) is used for the apps your themes have no icon for and for the icons and themes you marked: swipe right on an icon in the Custom icons screen, or on an active theme. The other theme icons keep their own shape.")],
    @[LMLocalized(@"Icon background"), LMLocalized(@"In Settings, light and dark mode each get a background: a color, a gradient or an image. It goes behind the marked icons and shows where their icon is transparent. It does not work with the icon shape \"Theme's own shape\".")],
    @[LMLocalized(@"Icon effects"), LMLocalized(@"Some themes bring an underlay and an overlay (Anemone effects). Turn on Icon effects in Settings to draw them into your icons.")],
    @[LMLocalized(@"Troubleshooting"), LMLocalized(@"If something doesn't look right, try Rebuild icons first. Diagnostics in Settings shows what happened and can be copied to share.")],
  ];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setToolbarHidden:YES animated:animated];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return _topics.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
  return _topics[section][0];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Topic" forIndexPath:indexPath];
  UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
  content.text = _topics[indexPath.section][1];
  content.textProperties.numberOfLines = 0;
  content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
  cell.contentConfiguration = content;
  cell.selectionStyle = UITableViewCellSelectionStyleNone;
  return cell;
}

@end
