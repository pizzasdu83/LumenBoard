#import "LMMarkdown.h"

#pragma mark - Helpers

static NSString *LMEscapeText(NSString *text) {
  NSMutableString *escaped = [text mutableCopy];
  // & that doesn't start an entity (&amp; &#38;)
  [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
  NSRegularExpression *entity = [NSRegularExpression regularExpressionWithPattern:@"&amp;(#?[A-Za-z0-9]+;)" options:0 error:nil];
  [entity replaceMatchesInString:escaped options:0 range:NSMakeRange(0, escaped.length) withTemplate:@"&$1"];
  [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
  [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
  return escaped;
}

static NSString *LMEscapeCode(NSString *text) {
  NSMutableString *escaped = [text mutableCopy];
  [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
  [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
  [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
  return escaped;
}

static NSString *LMEscapeAttribute(NSString *text) {
  return [text stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
}

static NSString *LMReplace(NSString *text, NSString *pattern, NSRegularExpressionOptions options, NSString *template) {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:nil];
  return [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:template];
}

// calls transform for every match and puts what it returns in place of the match
static NSString *LMReplaceWith(NSString *text, NSString *pattern, NSRegularExpressionOptions options, NSString *(^transform)(NSTextCheckingResult *match, NSString *source)) {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:nil];
  NSMutableString *result = [text mutableCopy];
  for (NSTextCheckingResult *match in [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)].reverseObjectEnumerator) {
    [result replaceCharactersInRange:match.range withString:transform(match, text)];
  }
  return result;
}

static NSString *LMGroup(NSTextCheckingResult *match, NSString *source, NSUInteger index) {
  NSRange range = [match rangeAtIndex:index];
  return range.location == NSNotFound ? @"" : [source substringWithRange:range];
}

#pragma mark - Inline

// parts that must not be touched by the other rules (code, tags, links...) are put aside and come back at the end
static NSString *LMStash(NSMutableArray<NSString *> *stash, NSString *html) {
  [stash addObject:html];
  return [NSString stringWithFormat:@"\uE000%lu\uE001", (unsigned long)stash.count - 1];
}

static NSString *LMRestore(NSString *text, NSMutableArray<NSString *> *stash) {
  NSString *current = text;
  for (int pass = 0; pass < 6 && [current containsString:@"\uE000"]; pass++) {
    current = LMReplaceWith(current, @"\uE000(\\d+)\uE001", 0, ^NSString *(NSTextCheckingResult *match, NSString *source) {
      NSUInteger index = (NSUInteger)[LMGroup(match, source, 1) integerValue];
      return index < stash.count ? stash[index] : @"";
    });
  }
  return current;
}

static NSString *LMEmphasis(NSString *text) {
  NSString *s = text;
  s = LMReplace(s, @"\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*", 0, @"<strong>$1</strong>");
  s = LMReplace(s, @"(?<![_\\w])__(?=\\S)(.+?)(?<=\\S)__(?![_\\w])", 0, @"<strong>$1</strong>");
  s = LMReplace(s, @"(?<![*\\w])\\*(?=\\S)([^*\\n]+?)(?<=\\S)\\*(?![*\\w])", 0, @"<em>$1</em>");
  s = LMReplace(s, @"(?<![_\\w])_(?=\\S)([^_\\n]+?)(?<=\\S)_(?![_\\w])", 0, @"<em>$1</em>");
  s = LMReplace(s, @"~~(?=\\S)(.+?)(?<=\\S)~~", 0, @"<del>$1</del>");
  return s;
}

static NSString *LMInline(NSString *text, NSMutableArray<NSString *> *stash) {
  NSString *s = text;
  // code
  s = LMReplaceWith(s, @"(`+)(.+?)\\1", 0, ^NSString *(NSTextCheckingResult *match, NSString *source) {
    NSString *code = [LMGroup(match, source, 2) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return LMStash(stash, [NSString stringWithFormat:@"<code>%@</code>", LMEscapeCode(code)]);
  });
  // <https://...> and <me@mail.com>
  s = LMReplaceWith(s, @"<((?:https?|mailto):[^>\\s]+)>", 0, ^NSString *(NSTextCheckingResult *match, NSString *source) {
    NSString *url = LMGroup(match, source, 1);
    return LMStash(stash, [NSString stringWithFormat:@"<a href=\"%@\">%@</a>", LMEscapeAttribute(url), LMEscapeText(url)]);
  });
  // HTML comments and tags stay as they are
  s = LMReplaceWith(s, @"<!--.*?-->", NSRegularExpressionDotMatchesLineSeparators, ^NSString *(NSTextCheckingResult *match, NSString *source) {
    return LMStash(stash, [source substringWithRange:match.range]);
  });
  s = LMReplaceWith(s, @"</?[A-Za-z][^>]*>", 0, ^NSString *(NSTextCheckingResult *match, NSString *source) {
    return LMStash(stash, [source substringWithRange:match.range]);
  });
  // line breaks: two spaces or a backslash at the end of a line
  s = LMReplaceWith(s, @"(?: {2,}|\\\\)\\n", 0, ^NSString *(NSTextCheckingResult *match, NSString *source) {
    return LMStash(stash, @"<br>\n");
  });
  // \* \_ \# ... are the characters themselves
  s = LMReplaceWith(s, @"\\\\([\\\\`*_{}\\[\\]()#+\\-.!|~<>])", 0, ^NSString *(NSTextCheckingResult *match, NSString *source) {
    return LMStash(stash, LMEscapeText(LMGroup(match, source, 1)));
  });
  s = LMEscapeText(s);
  // images, then links
  s = LMReplaceWith(s, @"!\\[([^\\]]*)\\]\\(\\s*([^)\\s]+)(?:\\s+&quot;([^)]*?)&quot;|\\s+\"([^\"]*)\")?\\s*\\)", 0, ^NSString *(NSTextCheckingResult *match, NSString *source) {
    NSString *title = LMGroup(match, source, 3).length ? LMGroup(match, source, 3) : LMGroup(match, source, 4);
    return LMStash(stash, [NSString stringWithFormat:@"<img src=\"%@\" alt=\"%@\"%@>", LMGroup(match, source, 2), LMEscapeAttribute(LMGroup(match, source, 1)), title.length ? [NSString stringWithFormat:@" title=\"%@\"", LMEscapeAttribute(title)] : @""]);
  });
  s = LMReplaceWith(s, @"\\[([^\\]]+)\\]\\(\\s*([^)\\s]+)(?:\\s+\"([^\"]*)\")?\\s*\\)", 0, ^NSString *(NSTextCheckingResult *match, NSString *source) {
    return LMStash(stash, [NSString stringWithFormat:@"<a href=\"%@\">%@</a>", LMGroup(match, source, 2), LMEmphasis(LMGroup(match, source, 1))]);
  });
  s = LMEmphasis(s);
  return LMRestore(s, stash);
}

#pragma mark - Blocks

static NSString *LMSlug(NSString *text) {
  NSString *s = LMReplace(text.lowercaseString, @"[^\\p{L}\\p{N}\\s_-]", 0, @"");
  s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  return [s stringByReplacingOccurrencesOfString:@" " withString:@"-"];
}

static NSInteger LMIndentWidth(NSString *line) {
  NSInteger width = 0;
  for (NSUInteger index = 0; index < line.length; index++) {
    unichar character = [line characterAtIndex:index];
    if (character == ' ') width++;
    else if (character == '\t') width += 4;
    else break;
  }
  return width;
}

static NSString *LMTrim(NSString *line) {
  return [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

static NSTextCheckingResult *LMListItem(NSString *line) {
  static NSRegularExpression *regex;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    regex = [NSRegularExpression regularExpressionWithPattern:@"^([ \\t]*)([-*+]|\\d{1,9}[.)])[ \\t]+(.*)$" options:0 error:nil];
  });
  return [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
}

static BOOL LMIsRule(NSString *trimmed) {
  NSString *compact = [trimmed stringByReplacingOccurrencesOfString:@" " withString:@""];
  if (compact.length < 3) return NO;
  for (NSString *mark in @[@"-", @"*", @"_"]) {
    if ([compact isEqualToString:[@"" stringByPaddingToLength:compact.length withString:mark startingAtIndex:0]]) return YES;
  }
  return NO;
}

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

static BOOL LMStartsHTMLBlock(NSString *trimmed) {
  static NSRegularExpression *blockTag, *onlyTags;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    blockTag = [NSRegularExpression regularExpressionWithPattern:@"^<(/?)(div|p|table|thead|tbody|tfoot|tr|td|th|caption|details|summary|ul|ol|li|pre|h[1-6]|section|article|aside|center|figure|figcaption|blockquote|hr|br|video|audio|iframe|style|dl|dt|dd|nav|header|footer|form|fieldset|picture|source|svg|noscript)(\\s|>|/|$)" options:NSRegularExpressionCaseInsensitive error:nil];
    onlyTags = [NSRegularExpression regularExpressionWithPattern:@"^(<[^>]+>\\s*)+$" options:0 error:nil];
  });
  if ([trimmed hasPrefix:@"<!--"]) return YES;
  NSRange all = NSMakeRange(0, trimmed.length);
  return [blockTag firstMatchInString:trimmed options:0 range:all] || [onlyTags firstMatchInString:trimmed options:0 range:all];
}

static BOOL LMStartsBlock(NSArray<NSString *> *lines, NSUInteger index) {
  NSString *line = lines[index], *trimmed = LMTrim(line);
  if (!trimmed.length) return YES;
  if ([trimmed hasPrefix:@"#"] || [trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"~~~"] || [trimmed hasPrefix:@">"]) return YES;
  if (LMIsRule(trimmed) || LMListItem(line) || LMStartsHTMLBlock(trimmed)) return YES;
  return [line containsString:@"|"] && index + 1 < lines.count && LMIsTableSeparator(lines[index + 1]);
}

static NSString *LMBlocks(NSArray<NSString *> *lines, NSMutableArray<NSString *> *stash);

// a list that starts at lines[*index], with its nested lists. *index ends after the list.
static NSString *LMList(NSArray<NSString *> *lines, NSUInteger *index, NSMutableArray<NSString *> *stash) {
  NSTextCheckingResult *first = LMListItem(lines[*index]);
  NSInteger base = LMIndentWidth(lines[*index]);
  NSString *marker = LMGroup(first, lines[*index], 2);
  BOOL ordered = ![@[@"-", @"*", @"+"] containsObject:marker];
  NSMutableString *html = [NSMutableString stringWithString:ordered ? [NSString stringWithFormat:@"<ol start=\"%ld\">\n", (long)MAX(1, marker.integerValue)] : @"<ul>\n"];
  NSMutableString *item = nil;
  while (*index < lines.count) {
    NSString *line = lines[*index];
    NSTextCheckingResult *match = LMListItem(line);
    if (match) {
      NSInteger indent = LMIndentWidth(line);
      if (indent < base) break;
      if (indent > base) {
        NSString *nested = LMList(lines, index, stash);
        if (item) [item appendFormat:@"\n%@", nested];
        else item = [nested mutableCopy];
        continue;
      }
      if (item) [html appendFormat:@"<li>%@</li>\n", item];
      NSString *content = LMGroup(match, line, 3);
      NSString *prefix = @"";
      if ([content hasPrefix:@"[ ] "]) { prefix = @"\u2610 "; content = [content substringFromIndex:4]; }
      else if ([content hasPrefix:@"[x] "] || [content hasPrefix:@"[X] "]) { prefix = @"\u2611 "; content = [content substringFromIndex:4]; }
      item = [[prefix stringByAppendingString:LMInline(content, stash)] mutableCopy];
      (*index)++;
      continue;
    }
    NSString *trimmed = LMTrim(line);
    if (!trimmed.length) {
      // a blank line: the list goes on if the next line is another item of it
      NSUInteger next = *index + 1;
      while (next < lines.count && !LMTrim(lines[next]).length) next++;
      if (next < lines.count && LMListItem(lines[next]) && LMIndentWidth(lines[next]) >= base) {
        *index = next;
        continue;
      }
      break;
    }
    // more text of the item
    if (item && LMIndentWidth(line) > base && !LMStartsHTMLBlock(trimmed)) {
      [item appendFormat:@" %@", LMInline(trimmed, stash)];
      (*index)++;
      continue;
    }
    break;
  }
  if (item) [html appendFormat:@"<li>%@</li>\n", item];
  [html appendString:ordered ? @"</ol>\n" : @"</ul>\n"];
  return html;
}

static NSString *LMBlocks(NSArray<NSString *> *lines, NSMutableArray<NSString *> *stash) {
  NSMutableString *html = [NSMutableString new];
  NSUInteger index = 0;
  while (index < lines.count) {
    NSString *line = lines[index], *trimmed = LMTrim(line);
    if (!trimmed.length) {
      index++;
      continue;
    }

    // fenced code
    if ([trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"~~~"]) {
      NSString *fence = [trimmed substringToIndex:3];
      NSString *language = LMTrim([trimmed substringFromIndex:3]);
      NSMutableArray *code = [NSMutableArray new];
      index++;
      while (index < lines.count && ![LMTrim(lines[index]) hasPrefix:fence]) [code addObject:lines[index++]];
      index++;
      [html appendFormat:@"<pre><code%@>%@</code></pre>\n", language.length ? [NSString stringWithFormat:@" class=\"language-%@\"", LMEscapeAttribute(language)] : @"", LMEscapeCode([code componentsJoinedByString:@"\n"])];
      continue;
    }

    // HTML: kept as it is until the next blank line (a comment, <pre> and <style> until their end)
    if (LMStartsHTMLBlock(trimmed)) {
      NSString *until = [trimmed hasPrefix:@"<!--"] ? @"-->" : ([trimmed.lowercaseString hasPrefix:@"<pre"] ? @"</pre>" : ([trimmed.lowercaseString hasPrefix:@"<style"] ? @"</style>" : nil));
      NSMutableArray *raw = [NSMutableArray new];
      while (index < lines.count) {
        NSString *current = lines[index];
        [raw addObject:current];
        index++;
        if (until) {
          if ([current.lowercaseString containsString:until]) break;
        } else if (index < lines.count && !LMTrim(lines[index]).length) {
          break;
        }
      }
      [html appendFormat:@"%@\n", [raw componentsJoinedByString:@"\n"]];
      continue;
    }

    // heading
    if ([trimmed hasPrefix:@"#"]) {
      NSUInteger level = 0;
      while (level < trimmed.length && [trimmed characterAtIndex:level] == '#') level++;
      if (level <= 6 && (level == trimmed.length || [trimmed characterAtIndex:level] == ' ')) {
        NSString *title = LMTrim(LMReplace([trimmed substringFromIndex:level], @"\\s#+\\s*$", 0, @""));
        [html appendFormat:@"<h%lu id=\"%@\">%@</h%lu>\n", (unsigned long)level, LMSlug(LMReplace(title, @"[*_`]", 0, @"")), LMInline(title, stash), (unsigned long)level];
        index++;
        continue;
      }
    }

    if (LMIsRule(trimmed)) {
      [html appendString:@"<hr>\n"];
      index++;
      continue;
    }

    // quote
    if ([trimmed hasPrefix:@">"]) {
      NSMutableArray *quote = [NSMutableArray new];
      while (index < lines.count && [LMTrim(lines[index]) hasPrefix:@">"]) {
        NSString *inner = [LMTrim(lines[index]) substringFromIndex:1];
        if ([inner hasPrefix:@" "]) inner = [inner substringFromIndex:1];
        [quote addObject:inner];
        index++;
      }
      [html appendFormat:@"<blockquote>\n%@</blockquote>\n", LMBlocks(quote, stash)];
      continue;
    }

    if (LMListItem(line)) {
      [html appendString:LMList(lines, &index, stash)];
      continue;
    }

    // table: a header line, a line of ---, then the rows
    if ([line containsString:@"|"] && index + 1 < lines.count && LMIsTableSeparator(lines[index + 1])) {
      NSArray<NSString *> *header = LMTableCells(line), *separators = LMTableCells(lines[index + 1]);
      NSMutableArray<NSString *> *alignment = [NSMutableArray new];
      for (NSString *separator in separators) {
        BOOL left = [separator hasPrefix:@":"], right = [separator hasSuffix:@":"];
        [alignment addObject:(left && right) ? @"center" : (right ? @"right" : (left ? @"left" : @""))];
      }
      NSString * (^cell)(NSString *, NSString *, NSUInteger) = ^NSString *(NSString *tag, NSString *content, NSUInteger column) {
        NSString *align = column < alignment.count ? alignment[column] : @"";
        return [NSString stringWithFormat:@"<%@%@>%@</%@>", tag, align.length ? [NSString stringWithFormat:@" style=\"text-align:%@\"", align] : @"", LMInline(content, stash), tag];
      };
      [html appendString:@"<table>\n<thead><tr>"];
      for (NSUInteger column = 0; column < header.count; column++) [html appendString:cell(@"th", header[column], column)];
      [html appendString:@"</tr></thead>\n<tbody>\n"];
      index += 2;
      while (index < lines.count && LMTrim(lines[index]).length && [lines[index] containsString:@"|"]) {
        NSArray<NSString *> *cells = LMTableCells(lines[index]);
        [html appendString:@"<tr>"];
        for (NSUInteger column = 0; column < header.count; column++) [html appendString:cell(@"td", column < cells.count ? cells[column] : @"", column)];
        [html appendString:@"</tr>\n"];
        index++;
      }
      [html appendString:@"</tbody>\n</table>\n"];
      continue;
    }

    // paragraph
    NSMutableArray *paragraph = [NSMutableArray arrayWithObject:line];
    index++;
    while (index < lines.count && !LMStartsBlock(lines, index)) [paragraph addObject:lines[index++]];
    [html appendFormat:@"<p>%@</p>\n", LMInline([paragraph componentsJoinedByString:@"\n"], stash)];
  }
  return html;
}

#pragma mark - Images and the page

static NSString *LMMimeType(NSString *extension) {
  NSDictionary *types = @{ @"png" : @"image/png", @"jpg" : @"image/jpeg", @"jpeg" : @"image/jpeg", @"gif" : @"image/gif", @"svg" : @"image/svg+xml", @"webp" : @"image/webp", @"heic" : @"image/heic" };
  return types[extension.lowercaseString];
}

// src="help/step1.png" -> the file of the app inside the page (the page has no folder of its own to load files from)
static NSString *LMInlineImages(NSString *html) {
  return LMReplaceWith(html, @"(\\ssrc\\s*=\\s*)([\"'])([^\"']+)\\2", NSRegularExpressionCaseInsensitive, ^NSString *(NSTextCheckingResult *match, NSString *source) {
    NSString *value = LMGroup(match, source, 3);
    NSString *original = [source substringWithRange:match.range];
    if ([value hasPrefix:@"http:"] || [value hasPrefix:@"https:"] || [value hasPrefix:@"data:"] || [value hasPrefix:@"//"]) return original;
    NSString *path = [value stringByRemovingPercentEncoding] ? : value;
    NSString *directory = path.stringByDeletingLastPathComponent;
    NSString *file = [[NSBundle mainBundle] pathForResource:path.lastPathComponent.stringByDeletingPathExtension ofType:path.pathExtension inDirectory:directory.length ? directory : nil];
    if (!file) file = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:path];
    NSString *mime = LMMimeType(file.pathExtension);
    NSData *data = mime ? [NSData dataWithContentsOfFile:file] : nil;
    if (!data || data.length > 8 * 1024 * 1024) return original;
    return [NSString stringWithFormat:@"%@\"data:%@;base64,%@\"", LMGroup(match, source, 1), mime, [data base64EncodedStringWithOptions:0]];
  });
}

@implementation LMMarkdown

+ (NSString *)pageFromMarkdown:(NSString *)markdown {
  NSString *normalized = [[markdown stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
  NSMutableArray<NSString *> *stash = [NSMutableArray new];
  NSString *body = LMInlineImages(LMBlocks([normalized componentsSeparatedByString:@"\n"], stash));
  NSString *style =
    @":root{color-scheme:light dark}"
    @"html{-webkit-text-size-adjust:100%;background:transparent}"
    @"body{font:-apple-system-body;color:CanvasText;margin:0;padding:12px 16px 40px;line-height:1.4;word-wrap:break-word}"
    @"h1{font:-apple-system-title1;font-weight:700;margin:1.2em 0 .4em}"
    @"h2{font:-apple-system-title2;font-weight:700;margin:1.2em 0 .4em}"
    @"h3{font:-apple-system-title3;font-weight:700;margin:1.1em 0 .4em}"
    @"h4,h5,h6{font:-apple-system-headline;margin:1em 0 .4em}"
    @"body>:first-child{margin-top:0}"
    @"p,ul,ol,table,pre,blockquote,details,figure{margin:0 0 .9em}"
    @"a{color:-apple-system-blue}"
    @"img{max-width:100%;height:auto;border-radius:10px;vertical-align:middle}"
    @"code{font:ui-monospace,Menlo,monospace;font-size:.9em;background:rgba(128,128,128,.18);padding:.1em .3em;border-radius:4px}"
    @"pre{background:rgba(128,128,128,.15);padding:10px 12px;border-radius:10px;overflow-x:auto}"
    @"pre code{background:none;padding:0}"
    @"blockquote{margin-left:0;padding:.2em 1em;border-left:3px solid rgba(128,128,128,.5);color:-apple-system-secondary-label}"
    @"table{border-collapse:collapse;display:block;overflow-x:auto;max-width:100%}"
    @"th,td{border:1px solid rgba(128,128,128,.4);padding:6px 10px;vertical-align:top}"
    @"th{background:rgba(128,128,128,.15)}"
    @"hr{border:0;border-top:1px solid rgba(128,128,128,.4);margin:1.2em 0}"
    @"ul,ol{padding-left:1.4em}li{margin:.2em 0}"
    @"details{background:rgba(128,128,128,.1);border-radius:10px;padding:8px 12px}summary{font-weight:600}";
  return [NSString stringWithFormat:@"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\"><style>%@</style></head><body>%@</body></html>", style, body];
}

@end
