#import "LMSettingsViewController.h"
#import "LMApplyViewController.h"
#import "LMDiagnosticsViewController.h"
#import "LMBackgroundViewController.h"
#import "LMShapeViewController.h"
#import "LMConfigStore.h"

typedef NS_ENUM(NSInteger, LMSettingsSection) {
  LMSettingsSectionIcons,
  LMSettingsSectionBackground,
  LMSettingsSectionIconCache,
  LMSettingsSectionTroubleshooting,
  LMSettingsSectionAbout,
  LMSettingsSectionCount,
};

typedef NS_ENUM(NSInteger, LMIconsRow) {
  LMIconsRowShape,
  LMIconsRowEffects,
  LMIconsRowKeepAppearance,
  LMIconsRowCount,
};

@implementation LMSettingsViewController

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = LMLocalized(@"Settings");
  self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOffLabelsChanged) name:UIAccessibilityOnOffSwitchLabelsDidChangeNotification object:nil];
}

- (void)onOffLabelsChanged {
  [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.tableView reloadData]; // the background modes may have changed
  [self.navigationController setToolbarHidden:YES animated:animated];
  // the shape may have changed on the shape page
  [self.tableView reloadData];
}

// With "On/Off Labels" (Settings > Accessibility) UISwitch draws its I/O labels through CoreImage, which crashes in
// this process on some devices (CIContext falls back to OpenGL). The rows get a checkmark instead then.
static BOOL LMUseCheckmarksForToggles(void) {
  return UIAccessibilityIsOnOffSwitchLabelsEnabled();
}

- (void)setToggleInCell:(UITableViewCell *)cell value:(BOOL)value action:(SEL)action {
  if (LMUseCheckmarksForToggles()) {
    cell.accessoryType = value ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return;
  }
  UISwitch *toggle = [UISwitch new];
  toggle.on = value;
  [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
  cell.accessoryView = toggle;
}

- (void)save {
  NSError *error;
  if ([[LMConfigStore sharedStore] save:&error]) return;
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:LMLocalized(@"Couldn't save") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)setIconEffects:(BOOL)on {
  [LMConfigStore sharedStore].iconEffects = on;
  [self save];
}

- (void)setKeepAppearance:(BOOL)on {
  [LMConfigStore sharedStore].keepIconsInDarkAndTinted = on;
  [self save];
}

- (void)iconEffectsChanged:(UISwitch *)toggle {
  [self setIconEffects:toggle.on];
}

- (void)keepAppearanceChanged:(UISwitch *)toggle {
  [self setKeepAppearance:toggle.on];
}

- (void)confirmRebuildIcons {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:LMLocalized(@"Rebuild icons?") message:LMLocalized(@"The icon cache of iOS is deleted, then SpringBoard restarts. iOS draws the icons again afterwards.") preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Rebuild & Respring") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
    [self presentViewController:[[LMApplyViewController alloc] initWithRebuildingOnly] animated:YES completion:nil];
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return LMSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  switch (section) {
    case LMSettingsSectionIcons: return LMIconsRowCount;
    case LMSettingsSectionBackground: return 2;
    case LMSettingsSectionIconCache: return 1;
    case LMSettingsSectionTroubleshooting: return 1;
    case LMSettingsSectionAbout: return 2;
  }
  return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
  switch (section) {
    case LMSettingsSectionIcons: return LMLocalized(@"Icons");
    case LMSettingsSectionBackground: return LMLocalized(@"Icon background");
    case LMSettingsSectionIconCache: return LMLocalized(@"Icon cache");
    case LMSettingsSectionTroubleshooting: return LMLocalized(@"Troubleshooting");
    case LMSettingsSectionAbout: return LMLocalized(@"About");
  }
  return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
  switch (section) {
    case LMSettingsSectionIcons: return LMLocalized(@"The icon shape is for the apps your themes have no icon for and for the icons and themes marked \"iOS shape\" (swipe right in their list). The other theme icons keep their own shape. Icon effects are the underlays and overlays some themes bring along (Anemone effects), they are drawn into every app icon. Tap Apply afterwards.");
    case LMSettingsSectionBackground: return LMLocalized(@"Fills the transparent parts of the icons marked \"iOS shape\" when the icon shape is \"iOS shape\". Light and dark mode each have their own background. Tap Apply afterwards.");
    case LMSettingsSectionIconCache: return LMLocalized(@"Rebuild icons deletes the icon cache of iOS and respring. Use it if icons still look wrong after installing or updating themes.");
    case LMSettingsSectionTroubleshooting: return LMLocalized(@"Shows what LumenBoard did in SpringBoard and iconservicesagent. Copy the report if your icons don't change.");
  }
  return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
  UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
  LMConfigStore *config = [LMConfigStore sharedStore];
  cell.selectionStyle = UITableViewCellSelectionStyleNone;

  if (indexPath.section == LMSettingsSectionIcons && indexPath.row == LMIconsRowShape) {
    content = [UIListContentConfiguration valueCellConfiguration];
    content.text = LMLocalized(@"Icon shape");
    content.secondaryText = [LMShapeViewController nameForShape:config.iconShape];
    content.image = [UIImage systemImageNamed:@"app"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (indexPath.section == LMSettingsSectionIcons && indexPath.row == LMIconsRowEffects) {
    content.text = LMLocalized(@"Icon effects");
    content.image = [UIImage systemImageNamed:@"square.3.layers.3d"];
    [self setToggleInCell:cell value:config.iconEffects action:@selector(iconEffectsChanged:)];
  } else if (indexPath.section == LMSettingsSectionIcons) {
    content.text = LMLocalized(@"Keep in dark & tinted mode");
    content.image = [UIImage systemImageNamed:@"circle.lefthalf.filled"];
    [self setToggleInCell:cell value:config.keepIconsInDarkAndTinted action:@selector(keepAppearanceChanged:)];
  } else if (indexPath.section == LMSettingsSectionBackground) {
    BOOL dark = indexPath.row == 1;
    NSString *mode = (dark ? config.backgroundDark : config.backgroundLight)[@"Mode"];
    content = [UIListContentConfiguration valueCellConfiguration];
    content.text = dark ? LMLocalized(@"Dark mode") : LMLocalized(@"Light mode");
    content.image = [UIImage systemImageNamed:dark ? @"moon" : @"sun.max"];
    content.secondaryText = [mode isEqualToString:@"color"] ? LMLocalized(@"Color") : ([mode isEqualToString:@"gradient"] ? LMLocalized(@"Gradient") : ([mode isEqualToString:@"image"] ? LMLocalized(@"Image") : LMLocalized(@"None")));
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (indexPath.section == LMSettingsSectionIconCache) {
    content.text = LMLocalized(@"Rebuild icons");
    content.textProperties.color = self.view.tintColor;
    content.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (indexPath.section == LMSettingsSectionTroubleshooting) {
    content.text = LMLocalized(@"Diagnostics");
    content.image = [UIImage systemImageNamed:@"stethoscope"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (indexPath.row == 0) {
    content = [UIListContentConfiguration valueCellConfiguration];
    content.text = LMLocalized(@"Version");
    content.secondaryText = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
  } else {
    content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = LMLocalized(@"Themes folder");
    content.secondaryText = LMThemesDirectoryDisplayName;
    content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
  }
  cell.contentConfiguration = content;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  LMConfigStore *config = [LMConfigStore sharedStore];
  if (indexPath.section == LMSettingsSectionIcons) {
    switch (indexPath.row) {
      case LMIconsRowShape:
        [self.navigationController pushViewController:[LMShapeViewController new] animated:YES];
        return;
      // only selectable when the toggles are checkmarks
      case LMIconsRowEffects:
        if (!LMUseCheckmarksForToggles()) return;
        [self setIconEffects:!config.iconEffects];
        break;
      case LMIconsRowKeepAppearance:
        if (!LMUseCheckmarksForToggles()) return;
        [self setKeepAppearance:!config.keepIconsInDarkAndTinted];
        break;
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
  } else if (indexPath.section == LMSettingsSectionBackground) {
    [self.navigationController pushViewController:[[LMBackgroundViewController alloc] initWithDark:indexPath.row == 1] animated:YES];
  } else if (indexPath.section == LMSettingsSectionIconCache) {
    [self confirmRebuildIcons];
  } else if (indexPath.section == LMSettingsSectionTroubleshooting) {
    [self.navigationController pushViewController:[LMDiagnosticsViewController new] animated:YES];
  }
}

@end
