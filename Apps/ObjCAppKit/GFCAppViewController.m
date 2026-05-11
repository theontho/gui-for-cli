#import "GFCAppViewController+Private.h"
#import "GFCBundleSession.h"
#import <objc/runtime.h>

void *GFCControlInfoKey = &GFCControlInfoKey;

@implementation GFCAppViewController

- (instancetype)initWithSession:(GFCBundleSession *)session {
  self = [super initWithNibName:nil bundle:nil];
  if (self != nil) {
    _session = session;
    _actionButtons = [NSMutableArray array];
  }
  return self;
}

- (void)loadView {
  NSSplitView *root = [[NSSplitView alloc] init];
  root.vertical = YES;
  root.dividerStyle = NSSplitViewDividerStyleThin;

  NSScrollView *sidebarScroll = [self scrollView];
  self.sidebarStack = [self verticalStackWithSpacing:8];
  self.sidebarStack.edgeInsets = NSEdgeInsetsMake(16, 12, 16, 12);
  sidebarScroll.documentView = self.sidebarStack;
  [sidebarScroll.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

  NSSplitView *detailSplit = [[NSSplitView alloc] init];
  detailSplit.vertical = NO;
  detailSplit.dividerStyle = NSSplitViewDividerStyleThin;

  NSScrollView *pageScroll = [self scrollView];
  self.pageStack = [self verticalStackWithSpacing:18];
  self.pageStack.edgeInsets = NSEdgeInsetsMake(24, 24, 24, 24);
  pageScroll.documentView = self.pageStack;

  NSView *outputPane = [self outputPane];
  [outputPane.heightAnchor constraintGreaterThanOrEqualToConstant:140].active = YES;
  [detailSplit addArrangedSubview:pageScroll];
  [detailSplit addArrangedSubview:outputPane];

  [root addArrangedSubview:sidebarScroll];
  [root addArrangedSubview:detailSplit];
  self.view = root;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  [self renderSidebar];
  [self renderSelectedPage];
  for (NSString *message in self.session.startupMessages) {
    [self appendOutput:message];
  }
}

- (void)renderSidebar {
  [self.sidebarStack setViews:@[] inGravity:NSStackViewGravityTop];
  [self.sidebarStack addArrangedSubview:[self bundleHeader]];

  NSString *previousGroup = nil;
  for (NSDictionary *page in self.session.pages) {
    NSString *group = [self string:page[@"sidebarGroup"]];
    if (group.length > 0 && ![group isEqualToString:previousGroup]) {
      NSTextField *groupLabel = [self label:group font:[NSFont systemFontOfSize:NSFont.smallSystemFontSize] textColor:NSColor.secondaryLabelColor];
      [self.sidebarStack addArrangedSubview:groupLabel];
      previousGroup = group;
    }

    NSButton *button = [NSButton buttonWithTitle:[self string:page[@"title"]] target:self action:@selector(selectPage:)];
    button.bezelStyle = NSBezelStyleRounded;
    button.alignment = NSTextAlignmentLeft;
    button.toolTip = [self string:page[@"summary"]];
    objc_setAssociatedObject(button, GFCControlInfoKey, [self string:page[@"id"]], OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self.sidebarStack addArrangedSubview:button];
  }
}

- (NSView *)bundleHeader {
  NSStackView *header = [self verticalStackWithSpacing:6];
  header.edgeInsets = NSEdgeInsetsMake(0, 0, 8, 0);
  NSString *title = [self string:self.session.manifest[@"displayName"]];
  NSString *summary = [self string:self.session.manifest[@"summary"]];
  [header addArrangedSubview:[self label:title font:[NSFont boldSystemFontOfSize:18] textColor:NSColor.labelColor]];
  if (summary.length > 0) {
    NSTextField *summaryLabel = [self wrappingLabel:summary font:[NSFont systemFontOfSize:NSFont.smallSystemFontSize] textColor:NSColor.secondaryLabelColor];
    [header addArrangedSubview:summaryLabel];
  }
  return header;
}

- (void)selectPage:(NSButton *)sender {
  NSString *pageID = objc_getAssociatedObject(sender, GFCControlInfoKey);
  self.session.selectedPageID = pageID;
  [self.session saveState];
  [self renderSidebar];
  [self renderSelectedPage];
}

- (void)renderSelectedPage {
  [self.pageStack setViews:@[] inGravity:NSStackViewGravityTop];
  [self.actionButtons removeAllObjects];
  NSDictionary *page = [self.session pageWithID:self.session.selectedPageID];
  if (page == nil) {
    [self.pageStack addArrangedSubview:[self wrappingLabel:@"No bundle pages are available." font:[NSFont systemFontOfSize:NSFont.systemFontSize] textColor:NSColor.secondaryLabelColor]];
    return;
  }

  [self.pageStack addArrangedSubview:[self pageHeader:page]];
  if ([[self string:page[@"id"]] isEqualToString:@"settings"]) {
    [self.pageStack addArrangedSubview:[self appearanceSection]];
    [self.pageStack addArrangedSubview:[self setupSection]];
  }
  for (NSDictionary *section in [self array:page[@"sections"]]) {
    [self.pageStack addArrangedSubview:[self sectionView:section]];
  }
  [self refreshActionButtons];
}

- (NSView *)pageHeader:(NSDictionary *)page {
  NSStackView *header = [self verticalStackWithSpacing:8];
  [header addArrangedSubview:[self label:[self string:page[@"title"]] font:[NSFont boldSystemFontOfSize:28] textColor:NSColor.labelColor]];
  NSString *summary = [self string:page[@"summary"]];
  if (summary.length > 0) {
    [header addArrangedSubview:[self wrappingLabel:summary font:[NSFont systemFontOfSize:NSFont.systemFontSize] textColor:NSColor.secondaryLabelColor]];
  }
  return header;
}

- (NSView *)sectionView:(NSDictionary *)section {
  NSBox *box = [[NSBox alloc] init];
  box.boxType = NSBoxCustom;
  box.cornerRadius = 8;
  box.borderColor = NSColor.separatorColor;
  box.fillColor = NSColor.controlBackgroundColor;
  box.contentViewMargins = NSMakeSize(16, 16);

  NSStackView *stack = [self verticalStackWithSpacing:12];
  NSString *title = [self string:section[@"title"]];
  if (title.length > 0) {
    [stack addArrangedSubview:[self label:title font:[NSFont boldSystemFontOfSize:17] textColor:NSColor.labelColor]];
  }
  NSString *subtitle = [self string:section[@"subtitle"]];
  if (subtitle.length > 0) {
    [stack addArrangedSubview:[self wrappingLabel:subtitle font:[NSFont systemFontOfSize:NSFont.systemFontSize] textColor:NSColor.secondaryLabelColor]];
  }
  for (NSDictionary *control in [self array:section[@"controls"]]) {
    [stack addArrangedSubview:[self controlView:control]];
  }
  NSArray *actions = [self array:section[@"actions"]];
  if (actions.count > 0) {
    NSStackView *actionRow = [self horizontalStackWithSpacing:8];
    for (NSDictionary *action in actions) {
      [actionRow addArrangedSubview:[self actionButton:action]];
    }
    [stack addArrangedSubview:actionRow];
  }
  box.contentView = stack;
  return box;
}

- (NSView *)outputPane {
  NSStackView *stack = [self verticalStackWithSpacing:8];
  stack.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
  NSStackView *header = [self horizontalStackWithSpacing:8];
  [header addArrangedSubview:[self label:@"Command output" font:[NSFont boldSystemFontOfSize:14] textColor:NSColor.labelColor]];
  NSButton *copy = [NSButton buttonWithTitle:@"Copy" target:self action:@selector(copyOutput:)];
  [header addArrangedSubview:copy];
  [stack addArrangedSubview:header];

  NSScrollView *scroll = [self scrollView];
  self.outputTextView = [[NSTextView alloc] init];
  self.outputTextView.editable = NO;
  self.outputTextView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
  scroll.documentView = self.outputTextView;
  [stack addArrangedSubview:scroll];
  return stack;
}

- (void)appendOutput:(NSString *)text {
  NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (trimmed.length == 0) {
    return;
  }
  NSString *next = [NSString stringWithFormat:@"%@\n", trimmed];
  [self.outputTextView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:next]];
  [self.outputTextView scrollRangeToVisible:NSMakeRange(self.outputTextView.string.length, 0)];
}

- (void)copyOutput:(NSButton *)sender {
  [NSPasteboard.generalPasteboard clearContents];
  [NSPasteboard.generalPasteboard setString:self.outputTextView.string forType:NSPasteboardTypeString];
}

- (NSScrollView *)scrollView {
  NSScrollView *scroll = [[NSScrollView alloc] init];
  scroll.hasVerticalScroller = YES;
  scroll.hasHorizontalScroller = NO;
  scroll.autohidesScrollers = YES;
  return scroll;
}

- (NSStackView *)verticalStackWithSpacing:(CGFloat)spacing {
  NSStackView *stack = [[NSStackView alloc] init];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = spacing;
  return stack;
}

- (NSStackView *)horizontalStackWithSpacing:(CGFloat)spacing {
  NSStackView *stack = [[NSStackView alloc] init];
  stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  stack.alignment = NSLayoutAttributeCenterY;
  stack.spacing = spacing;
  return stack;
}

- (NSTextField *)label:(NSString *)text font:(NSFont *)font textColor:(NSColor *)color {
  NSTextField *label = [NSTextField labelWithString:text];
  label.font = font;
  label.textColor = color;
  return label;
}

- (NSTextField *)wrappingLabel:(NSString *)text font:(NSFont *)font textColor:(NSColor *)color {
  NSTextField *label = [self label:text font:font textColor:color];
  label.lineBreakMode = NSLineBreakByWordWrapping;
  label.maximumNumberOfLines = 0;
  label.preferredMaxLayoutWidth = 760;
  return label;
}

- (NSDictionary *)dictionary:(id)value {
  return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

- (NSArray *)array:(id)value {
  return [value isKindOfClass:NSArray.class] ? value : @[];
}

- (NSString *)string:(id)value {
  if ([value isKindOfClass:NSString.class]) {
    return value;
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [value stringValue];
  }
  return @"";
}

@end
