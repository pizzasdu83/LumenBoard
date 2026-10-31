#import "LMAppPickerViewController.h"
#import "LMAppDelegate.h"

@interface LMAppPickerViewController () <UISearchResultsUpdating>
@end

@implementation LMAppPickerViewController {
  NSSet<NSString *> *_customized;
  void (^_pick)(LMAppInfo *);
  NSArray<LMAppInfo *> *_apps;
  NSArray<LMAppInfo *> *_visible;
  NSMutableDictionary<NSString *, UIImage *> *_icons;
  NSMutableSet<NSString *> *_requested;
  dispatch_queue_t _iconQueue;
  UISearchController *_search;
  UIActivityIndicatorView *_spinner;
}

- (instancetype)initWithCustomizedBundleIDs:(NSSet<NSString *> *)customized pick:(void (^)(LMAppInfo *))pick {
  if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
    _customized = [customized copy];
    _pick = [pick copy];
    _apps = @[];
    _visible = @[];
    _icons = [NSMutableDictionary new];
    _requested = [NSMutableSet new];
    _iconQueue = dispatch_queue_create("com.xsxs18.lumenboard.app-icons", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = LMLocalized(@"Choose an app");
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
  [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"App"];
  self.tableView.rowHeight = 60;

  _search = [[UISearchController alloc] initWithSearchResultsController:nil];
  _search.searchResultsUpdater = self;
  _search.obscuresBackgroundDuringPresentation = NO;
  _search.searchBar.placeholder = LMLocalized(@"Search apps");
  self.navigationItem.searchController = _search;
  self.navigationItem.hidesSearchBarWhenScrolling = NO;
  self.definesPresentationContext = YES;

  _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
  [_spinner startAnimating];
  self.tableView.backgroundView = _spinner;

  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSArray *apps = [LMAppCatalog installedApps];
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) strongSelf = weakSelf;
      if (!strongSelf) return;
      strongSelf->_apps = apps;
      [strongSelf->_spinner stopAnimating];
      [strongSelf updateSearchResultsForSearchController:strongSelf->_search];
    });
  });
}

- (void)cancel {
  [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
  NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (!query.length) {
    _visible = _apps;
  } else {
    _visible = [_apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(LMAppInfo *app, NSDictionary *bindings) {
      return [app.name localizedCaseInsensitiveContainsString:query] || [app.bundleID localizedCaseInsensitiveContainsString:query];
    }]];
  }
  [self.tableView reloadData];
}

#pragma mark - Icons

// the icon of an app takes a moment, so it is loaded one at a time and the row is refreshed when it's there
- (void)loadIconForBundleID:(NSString *)bundleID {
  if ([_requested containsObject:bundleID]) return;
  [_requested addObject:bundleID];
  __weak typeof(self) weakSelf = self;
  dispatch_async(_iconQueue, ^{
    UIImage *icon = [LMAppCatalog iconForBundleID:bundleID];
    if (!icon) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) strongSelf = weakSelf;
      if (!strongSelf) return;
      strongSelf->_icons[bundleID] = icon;
      for (NSIndexPath *indexPath in strongSelf.tableView.indexPathsForVisibleRows) {
        if (indexPath.row < (NSInteger)strongSelf->_visible.count && [strongSelf->_visible[indexPath.row].bundleID isEqualToString:bundleID])
          [strongSelf.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
      }
    });
  });
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return _visible.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"App" forIndexPath:indexPath];
  LMAppInfo *app = _visible[indexPath.row];
  UIImage *icon = _icons[app.bundleID];
  if (!icon) [self loadIconForBundleID:app.bundleID];

  UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
  content.text = app.name;
  content.secondaryText = [_customized containsObject:app.bundleID.lowercaseString] ? [NSString stringWithFormat:@"%@ · %@", app.bundleID, LMLocalized(@"Custom icon")] : app.bundleID;
  content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
  content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
  content.image = icon ? : [UIImage systemImageNamed:@"app"];
  content.imageProperties.maximumSize = CGSizeMake(42, 42);
  content.imageProperties.reservedLayoutSize = CGSizeMake(42, 42);
  content.imageProperties.cornerRadius = 9.5;
  content.imageProperties.tintColor = [UIColor tertiaryLabelColor];
  cell.contentConfiguration = content;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if (indexPath.row >= (NSInteger)_visible.count) return;
  LMAppInfo *app = _visible[indexPath.row];
  void (^pick)(LMAppInfo *) = _pick;
  // dismissing from the presenting side also closes the search results
  [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:^{
    pick(app);
  }];
}

@end
