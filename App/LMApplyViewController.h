#import "LMAppDelegate.h"

// Sheet shown while SpringBoard pre-renders the theme icons and resprings.
@interface LMApplyViewController : UIViewController
- (instancetype)initWithClearingIconCache:(BOOL)clearIconCache;
// only deletes the icon cache of iOS and resprings, the theme config isn't applied
- (instancetype)initWithRebuildingOnly;
@end
