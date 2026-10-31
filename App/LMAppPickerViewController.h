#import "LMAppCatalog.h"

NS_ASSUME_NONNULL_BEGIN

// Searchable list of the installed apps. Shown in a navigation controller, dismisses itself, then calls pick.
@interface LMAppPickerViewController : UITableViewController

// customized: lowercased bundle ids that already have a custom icon
- (instancetype)initWithCustomizedBundleIDs:(NSSet<NSString *> *)customized pick:(void (^)(LMAppInfo *app))pick;

@end

NS_ASSUME_NONNULL_END
