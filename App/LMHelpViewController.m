#import "LMHelpViewController.h"

// "How does this work?" shows HowItWorks.md, drawn with normal iOS views (no web view): headings, paragraphs, lists, quotes, code blocks,
// **bold**, *italic*, `code`, [links](https://...), <br> for a new line, images (![alt](help/step1.png) or <img src="..." width="200"> alone
// on a line, a file of the app or an https address) and tables (| a | b | with a |---|---| line under the first row).

#pragma mark - Text

static UIFont *LMFontWithTraits(UIFont *font, UIFontDescriptorSymbolicTraits traits) {
  UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorWithSymbolicTraits:font.fontDescriptor.symbolicTraits | traits];
  return descriptor ? [UIFont fontWithDescriptor:descriptor size:font.pointSize] : font;
}

static NSString *LMTrim(NSString *string) {
  return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// calls style for every match of pattern (first group = the text inside), from the end so the ranges stay right
static void LMApplyPattern(NSMutableAttributedString *text, NSString *pattern, void (^style)(NSMutableAttributedString *inner, NSTextCheckingResult *match, NSString *source)) {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
  NSString *source = text.string;
  for (NSTextCheckingResult *match in [regex matchesInString:source options:0 range:NSMakeRange(0, source.length)].reverseObjectEnumerator) {
    NSMutableAttributedString *inner = [[text attributedSubstringFromRange:[match rangeAtIndex:1]] mutableCopy];
    style(inner, match, source);
    [text replaceCharactersInRange:match.range withAttributedString:inner];
  }
}

static NSMutableAttributedString *LMInline(NSString *string, UIFont *font, UIColor *color) {
  // <br> is a new line
  NSString *plain = [[NSRegularExpression regularExpressionWithPattern:@"<br\\s*/?>" options:NSRegularExpressionCaseInsensitive error:nil] stringByReplacingMatchesInString:string options:0 range:NSMakeRange(0, string.length) withTemplate:@"\n"];
  NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:plain attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName : color }];
  LMApplyPattern(text, @"\\[([^\\]]+)\\]\\(([^)\\s]+)\\)", ^(NSMutableAttributedString *inner, NSTextCheckingResult *match, NSString *source) {
    NSURL *url = [NSURL URLWithString:[source substringWithRange:[match rangeAtIndex:2]]];
    if (url) [inner addAttribute:NSLinkAttributeName value:url range:NSMakeRange(0, inner.length)];
  });
  LMApplyPattern(text, @"`([^`\\n]+)`", ^(NSMutableAttributedString *inner, NSTextCheckingResult *match, NSString *source) {
    [inner addAttributes:@{ NSFontAttributeName : [UIFont monospacedSystemFontOfSize:font.pointSize * 0.9 weight:UIFontWeightRegular], NSBackgroundColorAttributeName : [UIColor tertiarySystemFillColor] } range:NSMakeRange(0, inner.length)];
  });
  LMApplyPattern(text, @"\\*\\*([^*\\n]+)\\*\\*", ^(NSMutableAttributedString *inner, NSTextCheckingResult *match, NSString *source) {
    [inner enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, inner.length) options:0 usingBlock:^(UIFont *value, NSRange range, BOOL *stop) {
      [inner addAttribute:NSFontAttributeName value:LMFontWithTraits(value ? : font, UIFontDescriptorTraitBold) range:range];
    }];
  });
  // *italic* and _italic_ (not the underscores inside a word)
  void (^italic)(NSMutableAttributedString *, NSTextCheckingResult *, NSString *) = ^(NSMutableAttributedString *inner, NSTextCheckingResult *match, NSString *source) {
    [inner enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, inner.length) options:0 usingBlock:^(UIFont *value, NSRange range, BOOL *stop) {
      [inner addAttribute:NSFontAttributeName value:LMFontWithTraits(value ? : font, UIFontDescriptorTraitItalic) range:range];
    }];
  };
  LMApplyPattern(text, @"(?<![*\\w])\\*([^*\\n]+)\\*(?![*\\w])", italic);
  LMApplyPattern(text, @"(?<![_\\w])_([^_\\n]+)_(?![_\\w])", italic);
  return text;
}

// one block (a paragraph, a heading, a list item...) with its spacing, and a new line after it
static void LMAppendBlock(NSMutableAttributedString *result, NSAttributedString *text, CGFloat indent, CGFloat hanging, CGFloat spaceBefore, CGFloat spaceAfter) {
  NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
  style.firstLineHeadIndent = indent;
  style.headIndent = indent + hanging;
  style.paragraphSpacingBefore = spaceBefore;
  style.paragraphSpacing = spaceAfter;
  if (hanging > 0) style.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:indent + hanging options:@{}]];
  NSMutableAttributedString *block = [text mutableCopy];
  [block appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
  [block addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, block.length)];
  [result appendAttributedString:block];
}

// headings, paragraphs, lists, quotes, code blocks and rules
static NSAttributedString *LMRenderText(NSString *markdown) {
  NSMutableAttributedString *result = [NSMutableAttributedString new];
  UIFont *body = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
  UIColor *label = [UIColor labelColor], *secondary = [UIColor secondaryLabelColor];
  NSRegularExpression *bullet = [NSRegularExpression regularExpressionWithPattern:@"^(\\s*)[-*+]\\s+(.*)$" options:0 error:nil];
  NSRegularExpression *numbered = [NSRegularExpression regularExpressionWithPattern:@"^(\\s*)(\\d+)[.)]\\s+(.*)$" options:0 error:nil];

  NSMutableArray<NSString *> *paragraph = [NSMutableArray new];
  NSMutableArray<NSString *> *code = nil;
  void (^flush)(void) = ^{
    if (!paragraph.count) return;
    LMAppendBlock(result, LMInline([paragraph componentsJoinedByString:@" "], body, label), 0, 0, 0, 10);
    [paragraph removeAllObjects];
  };

  for (NSString *line in [markdown componentsSeparatedByString:@"\n"]) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmed hasPrefix:@"```"]) {
      if (code) {
        UIFont *mono = [UIFont monospacedSystemFontOfSize:body.pointSize * 0.9 weight:UIFontWeightRegular];
        LMAppendBlock(result, [[NSAttributedString alloc] initWithString:[code componentsJoinedByString:@"\n"] attributes:@{ NSFontAttributeName : mono, NSForegroundColorAttributeName : label, NSBackgroundColorAttributeName : [UIColor tertiarySystemFillColor] }], 0, 0, 0, 10);
        code = nil;
      } else {
        flush();
        code = [NSMutableArray new];
      }
      continue;
    }
    if (code) {
      [code addObject:line];
      continue;
    }
    if (!trimmed.length) {
      flush();
      continue;
    }
    NSRange all = NSMakeRange(0, line.length);
    if ([trimmed hasPrefix:@"#"]) {
      flush();
      NSUInteger level = 0;
      while (level < trimmed.length && [trimmed characterAtIndex:level] == '#') level++;
      NSString *title = [[trimmed substringFromIndex:level] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      UIFontTextStyle textStyle = level == 1 ? UIFontTextStyleTitle1 : (level == 2 ? UIFontTextStyleTitle2 : (level == 3 ? UIFontTextStyleTitle3 : UIFontTextStyleHeadline));
      UIFont *font = LMFontWithTraits([UIFont preferredFontForTextStyle:textStyle], UIFontDescriptorTraitBold);
      LMAppendBlock(result, LMInline(title, font, label), 0, 0, result.length ? 14 : 0, 8);
    } else if ([trimmed isEqualToString:@"---"] || [trimmed isEqualToString:@"***"] || [trimmed isEqualToString:@"___"]) {
      flush();
      LMAppendBlock(result, [[NSAttributedString alloc] initWithString:@"────────" attributes:@{ NSFontAttributeName : body, NSForegroundColorAttributeName : [UIColor separatorColor] }], 0, 0, 4, 8);
    } else if ([trimmed hasPrefix:@">"]) {
      flush();
      NSString *quote = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      LMAppendBlock(result, LMInline(quote, LMFontWithTraits(body, UIFontDescriptorTraitItalic), secondary), 16, 0, 0, 10);
    } else if ([bullet firstMatchInString:line options:0 range:all]) {
      flush();
      NSTextCheckingResult *match = [bullet firstMatchInString:line options:0 range:all];
      CGFloat indent = [match rangeAtIndex:1].length * 8;
      NSMutableAttributedString *item = [[NSMutableAttributedString alloc] initWithString:@"•\t" attributes:@{ NSFontAttributeName : body, NSForegroundColorAttributeName : label }];
      [item appendAttributedString:LMInline([line substringWithRange:[match rangeAtIndex:2]], body, label)];
      LMAppendBlock(result, item, 4 + indent, 18, 0, 4);
    } else if ([numbered firstMatchInString:line options:0 range:all]) {
      flush();
      NSTextCheckingResult *match = [numbered firstMatchInString:line options:0 range:all];
      CGFloat indent = [match rangeAtIndex:1].length * 8;
      NSMutableAttributedString *item = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@.\t", [line substringWithRange:[match rangeAtIndex:2]]] attributes:@{ NSFontAttributeName : body, NSForegroundColorAttributeName : label }];
      [item appendAttributedString:LMInline([line substringWithRange:[match rangeAtIndex:3]], body, label)];
      LMAppendBlock(result, item, 4 + indent, 22, 0, 4);
    } else {
      [paragraph addObject:trimmed];
    }
  }
  flush();
  return result;
}

#pragma mark - Tables and images

static BOOL LMIsTableSeparator(NSString *line) {
  static NSRegularExpression *regex;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    regex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*\\|?\\s*:?-+:?\\s*(\\|\\s*:?-+:?\\s*)*\\|?\\s*$" options:0 error:nil];
  });
  return [line containsString:@"|"] && [line containsString:@"-"] && [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
}

// the cells of a table row, "\|" is a | in a cell
static NSArray<NSString *> *LMTableCells(NSString *line) {
  NSString *row = LMTrim(line);
  if ([row hasPrefix:@"|"]) row = [row substringFromIndex:1];
  if ([row hasSuffix:@"|"] && ![row hasSuffix:@"\\|"]) row = [row substringToIndex:row.length - 1];
  NSMutableArray *cells = [NSMutableArray new];
  NSMutableString *cell = [NSMutableString new];
  for (NSUInteger index = 0; index < row.length; index++) {
    unichar character = [row characterAtIndex:index];
    if (character == '\\' && index + 1 < row.length && [row characterAtIndex:index + 1] == '|') {
      [cell appendString:@"|"];
      index++;
    } else if (character == '|') {
      [cells addObject:LMTrim(cell)];
      cell = [NSMutableString new];
    } else {
      [cell appendFormat:@"%C", character];
    }
  }
  [cells addObject:LMTrim(cell)];
  return cells;
}

// the markdown cut into text, tables and images (an image alone on its line)
static NSArray<NSDictionary *> *LMSegments(NSString *markdown) {
  NSString *normalized = [[markdown stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
  NSArray<NSString *> *lines = [normalized componentsSeparatedByString:@"\n"];
  NSMutableArray<NSDictionary *> *segments = [NSMutableArray new];
  NSMutableArray<NSString *> *text = [NSMutableArray new];
  void (^flushText)(void) = ^{
    NSString *joined = [text componentsJoinedByString:@"\n"];
    if (LMTrim(joined).length) [segments addObject:@{ @"type" : @"text", @"text" : joined }];
    [text removeAllObjects];
  };
  NSString *imageToken = @"(?:!\\[[^\\]]*\\]\\(\\s*[^)\\s]+(?:\\s+\"[^\"]*\")?\\s*\\)|<img\\b[^>]*>)";
  NSRegularExpression *imageLine = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^(?:%@\\s*(?:<br\\s*/?>)?\\s*)+$", imageToken] options:NSRegularExpressionCaseInsensitive error:nil];
  NSRegularExpression *imageParts = [NSRegularExpression regularExpressionWithPattern:@"!\\[([^\\]]*)\\]\\(\\s*([^)\\s]+)(?:\\s+\"[^\"]*\")?\\s*\\)|<img\\b([^>]*)>" options:NSRegularExpressionCaseInsensitive error:nil];

  BOOL fenced = NO;
  for (NSUInteger index = 0; index < lines.count; index++) {
    NSString *line = lines[index], *trimmed = LMTrim(line);
    if ([trimmed hasPrefix:@"```"]) {
      fenced = !fenced;
      [text addObject:line];
      continue;
    }
    if (fenced) {
      [text addObject:line];
      continue;
    }

    // table: a header line, a line of ---, then the rows
    if ([line containsString:@"|"] && index + 1 < lines.count && LMIsTableSeparator(lines[index + 1])) {
      flushText();
      NSMutableArray *rows = [NSMutableArray arrayWithObject:LMTableCells(line)];
      NSMutableArray *alignment = [NSMutableArray new];
      for (NSString *separator in LMTableCells(lines[index + 1])) {
        BOOL left = [separator hasPrefix:@":"], right = [separator hasSuffix:@":"];
        [alignment addObject:@((left && right) ? NSTextAlignmentCenter : (right ? NSTextAlignmentRight : NSTextAlignmentLeft))];
      }
      index += 2;
      while (index < lines.count && LMTrim(lines[index]).length && [lines[index] containsString:@"|"]) [rows addObject:LMTableCells(lines[index++])];
      index--; // the loop moves on by one
      [segments addObject:@{ @"type" : @"table", @"rows" : rows, @"alignment" : alignment }];
      continue;
    }

    // images alone on their line
    if ([imageLine firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)]) {
      flushText();
      for (NSTextCheckingResult *match in [imageParts matchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)]) {
        NSString *source = nil, *alt = @"";
        CGFloat width = 0;
        if ([match rangeAtIndex:2].location != NSNotFound) {
          source = [trimmed substringWithRange:[match rangeAtIndex:2]];
          alt = [trimmed substringWithRange:[match rangeAtIndex:1]];
        } else {
          NSString *attributes = [trimmed substringWithRange:[match rangeAtIndex:3]];
          NSTextCheckingResult *src = [[NSRegularExpression regularExpressionWithPattern:@"src\\s*=\\s*[\"']([^\"']+)[\"']" options:NSRegularExpressionCaseInsensitive error:nil] firstMatchInString:attributes options:0 range:NSMakeRange(0, attributes.length)];
          NSTextCheckingResult *altMatch = [[NSRegularExpression regularExpressionWithPattern:@"alt\\s*=\\s*[\"']([^\"']*)[\"']" options:NSRegularExpressionCaseInsensitive error:nil] firstMatchInString:attributes options:0 range:NSMakeRange(0, attributes.length)];
          NSTextCheckingResult *widthMatch = [[NSRegularExpression regularExpressionWithPattern:@"width\\s*=\\s*[\"']?(\\d+)" options:NSRegularExpressionCaseInsensitive error:nil] firstMatchInString:attributes options:0 range:NSMakeRange(0, attributes.length)];
          if (src) source = [attributes substringWithRange:[src rangeAtIndex:1]];
          if (altMatch) alt = [attributes substringWithRange:[altMatch rangeAtIndex:1]];
          if (widthMatch) width = [[attributes substringWithRange:[widthMatch rangeAtIndex:1]] doubleValue];
        }
        if (source.length) [segments addObject:@{ @"type" : @"image", @"source" : source, @"alt" : alt, @"width" : @(width) }];
      }
      continue;
    }
    [text addObject:line];
  }
  flushText();
  return segments;
}

// a file of the app (Resources) or nil
static UIImage *LMBundleImage(NSString *source) {
  NSString *path = [source stringByRemovingPercentEncoding] ? : source;
  NSString *directory = path.stringByDeletingLastPathComponent;
  NSString *file = [[NSBundle mainBundle] pathForResource:path.lastPathComponent.stringByDeletingPathExtension ofType:path.pathExtension inDirectory:directory.length ? directory : nil];
  if (!file) file = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:path];
  return [UIImage imageWithContentsOfFile:file];
}

#pragma mark - Screen

@interface LMHelpViewController () <UITextViewDelegate>
@end

@implementation LMHelpViewController {
  UIStackView *_stack;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = LMLocalized(@"How does this work?");
  self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
  self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

  UIScrollView *scroll = [UIScrollView new];
  scroll.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.alwaysBounceVertical = YES;
  [self.view addSubview:scroll];
  _stack = [UIStackView new];
  _stack.axis = UILayoutConstraintAxisVertical;
  _stack.spacing = 12;
  _stack.translatesAutoresizingMaskIntoConstraints = NO;
  [scroll addSubview:_stack];
  [NSLayoutConstraint activateConstraints:@[
    [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
    [_stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-40],
    [_stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:16],
    [_stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-16],
  ]];

  // HowItWorks.md in the app (Resources). A file in a language folder (de.lproj/HowItWorks.md) is used for that language.
  NSString *path = [[NSBundle mainBundle] pathForResource:@"HowItWorks" ofType:@"md"];
  NSString *markdown = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
  if (!markdown.length) markdown = LMLocalized(@"The help text (HowItWorks.md) is missing from the app.");

  for (NSDictionary *segment in LMSegments(markdown)) {
    NSString *type = segment[@"type"];
    UIView *view = [type isEqualToString:@"table"] ? [self tableViewForSegment:segment] : ([type isEqualToString:@"image"] ? [self imageViewForSegment:segment] : [self textViewForMarkdown:segment[@"text"]]);
    [_stack addArrangedSubview:view];
  }
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setToolbarHidden:YES animated:animated];
}

#pragma mark - Views

- (UIView *)textViewForMarkdown:(NSString *)markdown {
  UITextView *textView = [UITextView new];
  textView.scrollEnabled = NO;
  textView.editable = NO;
  textView.backgroundColor = [UIColor clearColor];
  textView.textContainerInset = UIEdgeInsetsZero;
  textView.textContainer.lineFragmentPadding = 0;
  textView.delegate = self;
  textView.attributedText = LMRenderText(markdown);
  return textView;
}

- (UIView *)tableViewForSegment:(NSDictionary *)segment {
  NSArray<NSArray<NSString *> *> *rows = segment[@"rows"];
  NSArray<NSNumber *> *alignment = segment[@"alignment"];
  NSUInteger columns = [rows.firstObject count];
  UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
  UIStackView *table = [UIStackView new];
  table.axis = UILayoutConstraintAxisVertical;
  table.spacing = -0.5; // the borders of neighbours share a line
  for (NSUInteger rowIndex = 0; rowIndex < rows.count; rowIndex++) {
    BOOL header = rowIndex == 0;
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.alignment = UIStackViewAlignmentFill;
    row.spacing = -0.5;
    for (NSUInteger column = 0; column < columns; column++) {
      NSString *content = column < rows[rowIndex].count ? rows[rowIndex][column] : @"";
      UILabel *label = [UILabel new];
      label.numberOfLines = 0;
      label.textAlignment = column < alignment.count ? (NSTextAlignment)alignment[column].integerValue : NSTextAlignmentLeft;
      label.attributedText = LMInline(content, header ? LMFontWithTraits(font, UIFontDescriptorTraitBold) : font, [UIColor labelColor]);
      label.translatesAutoresizingMaskIntoConstraints = NO;
      UIView *cell = [UIView new];
      cell.layer.borderWidth = 0.5;
      cell.layer.borderColor = [UIColor separatorColor].CGColor;
      cell.backgroundColor = header ? [UIColor secondarySystemFillColor] : [UIColor clearColor];
      [cell addSubview:label];
      [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:cell.topAnchor constant:6],
        [label.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-6],
        [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
        [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
      ]];
      [row addArrangedSubview:cell];
    }
    [table addArrangedSubview:row];
  }
  return table;
}

- (UIView *)imageViewForSegment:(NSDictionary *)segment {
  NSString *source = segment[@"source"];
  CGFloat width = [segment[@"width"] doubleValue];
  UIView *container = [UIView new];
  UIImageView *imageView = [UIImageView new];
  imageView.translatesAutoresizingMaskIntoConstraints = NO;
  imageView.contentMode = UIViewContentModeScaleAspectFit;
  imageView.layer.cornerRadius = 10;
  imageView.clipsToBounds = YES;
  imageView.isAccessibilityElement = YES;
  imageView.accessibilityLabel = segment[@"alt"];
  [container addSubview:imageView];
  [NSLayoutConstraint activateConstraints:@[
    [imageView.topAnchor constraintEqualToAnchor:container.topAnchor],
    [imageView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    [imageView.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
    [imageView.widthAnchor constraintLessThanOrEqualToAnchor:container.widthAnchor],
  ]];

  // as wide as asked or as the picture is (never wider than the page), as high as its proportions say
  void (^show)(UIImage *) = ^(UIImage *image) {
    if (!image || image.size.width <= 0) return;
    imageView.image = image;
    NSLayoutConstraint *wide = [imageView.widthAnchor constraintEqualToConstant:width > 0 ? width : image.size.width];
    wide.priority = 999;
    wide.active = YES;
    [imageView.heightAnchor constraintEqualToAnchor:imageView.widthAnchor multiplier:image.size.height / image.size.width].active = YES;
    [container.superview setNeedsLayout];
  };
  if ([source hasPrefix:@"http://"] || [source hasPrefix:@"https://"]) {
    NSURL *url = [NSURL URLWithString:source];
    if (url) [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      UIImage *image = data ? [UIImage imageWithData:data] : nil;
      dispatch_async(dispatch_get_main_queue(), ^{ show(image); });
    }] resume];
  } else {
    show(LMBundleImage(source));
  }
  return container;
}

// links open outside the app
- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction {
  return YES;
}

@end
