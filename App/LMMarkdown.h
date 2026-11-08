#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Markdown to a web page, for the "How does this work?" screen. Understands headings, paragraphs, lists (also nested and task lists),
// tables, images, links, quotes, code, rules, **bold**, *italic*, ~~strike~~, and HTML (blocks and inline tags are kept as they are).
// Images that are files of the app (![](help/step1.png) or <img src="help/step1.png">) are put in the page, https images are loaded.
@interface LMMarkdown : NSObject

+ (NSString *)pageFromMarkdown:(NSString *)markdown;

@end

NS_ASSUME_NONNULL_END
