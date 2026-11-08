#import "LMHelpViewController.h"
#import "LMMarkdown.h"
#import <WebKit/WebKit.h>

@interface LMHelpViewController () <WKNavigationDelegate>
@end

@implementation LMHelpViewController {
  WKWebView *_webView;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = LMLocalized(@"How does this work?");
  self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
  self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

  // HowItWorks.md in the app (Resources). A file in a language folder (de.lproj/HowItWorks.md) is used for that language.
  NSString *path = [[NSBundle mainBundle] pathForResource:@"HowItWorks" ofType:@"md"];
  NSString *markdown = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
  if (!markdown.length) markdown = LMLocalized(@"The help text (HowItWorks.md) is missing from the app.");

  // the page is the app's own, nothing in it needs to run code
  WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
  configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
  _webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
  _webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  _webView.navigationDelegate = self;
  _webView.opaque = NO;
  _webView.backgroundColor = [UIColor clearColor];
  _webView.scrollView.backgroundColor = [UIColor clearColor];
  [self.view addSubview:_webView];
  [_webView loadHTMLString:[LMMarkdown pageFromMarkdown:markdown] baseURL:nil];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setToolbarHidden:YES animated:animated];
}

// links to the web (and mail, phone) open outside the app, links inside the page (#section) stay
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  NSURL *url = navigationAction.request.URL;
  NSString *scheme = url.scheme.lowercaseString;
  if (navigationAction.navigationType == WKNavigationTypeLinkActivated && ([@[@"http", @"https", @"mailto", @"tel"] containsObject:scheme])) {
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    decisionHandler(WKNavigationActionPolicyCancel);
    return;
  }
  decisionHandler(WKNavigationActionPolicyAllow);
}

@end
