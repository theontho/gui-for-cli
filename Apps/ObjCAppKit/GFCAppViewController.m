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
    _tableControllers = [NSMutableArray array];
  }
  return self;
}

- (void)loadView {
  NSSplitView *root = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 1180, 820)];
  root.vertical = YES;
  root.dividerStyle = NSSplitViewDividerStyleThin;
  root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.rootSplitView = root;

  NSScrollView *sidebarScroll = [self scrollView];
  self.sidebarStack = [self verticalStackWithSpacing:8];
  self.sidebarStack.alignment = NSLayoutAttributeWidth;
  self.sidebarStack.edgeInsets = NSEdgeInsetsMake(16, 12, 16, 12);
  [self installDocumentView:self.sidebarStack inScrollView:sidebarScroll];
  [sidebarScroll.widthAnchor constraintGreaterThanOrEqualToConstant:240].active = YES;
  [sidebarScroll.widthAnchor constraintLessThanOrEqualToConstant:340].active = YES;

  NSSplitView *detailSplit = [[NSSplitView alloc] init];
  detailSplit.vertical = NO;
  detailSplit.dividerStyle = NSSplitViewDividerStyleThin;
  self.detailSplitView = detailSplit;

  NSScrollView *pageScroll = [self scrollView];
  self.pageStack = [self verticalStackWithSpacing:18];
  self.pageStack.alignment = NSLayoutAttributeWidth;
  self.pageStack.edgeInsets = NSEdgeInsetsMake(24, 24, 24, 24);
  [self installDocumentView:self.pageStack inScrollView:pageScroll];
  [pageScroll.widthAnchor constraintGreaterThanOrEqualToConstant:680].active = YES;

  NSView *outputPane = [self outputPane];
  [outputPane.heightAnchor constraintGreaterThanOrEqualToConstant:140].active = YES;
  [detailSplit addArrangedSubview:pageScroll];
  [detailSplit addArrangedSubview:outputPane];

  [root addArrangedSubview:sidebarScroll];
  [root addArrangedSubview:detailSplit];
  [root setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:0];
  [detailSplit setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:0];
  [detailSplit setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:1];
  self.view = root;
  self.preferredContentSize = NSMakeSize(1180, 820);
}

- (void)viewDidLoad {
  [super viewDidLoad];
  [self renderSidebar];
  [self renderSelectedPage];
  for (NSString *message in self.session.startupMessages) {
    [self appendOutput:message];
  }
}

- (void)viewDidLayout {
  [super viewDidLayout];
  [self applyInitialSplitPositionsIfNeeded];
}

- (void)applyInitialSplitPositionsIfNeeded {
  if (self.didSetInitialSplitPositions) {
    return;
  }
  if (self.rootSplitView.bounds.size.width <= 0 || self.detailSplitView.bounds.size.height <= 0) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self applyInitialSplitPositionsIfNeeded];
    });
    return;
  }

  CGFloat sidebarWidth = MIN(300, MAX(260, self.rootSplitView.bounds.size.width * 0.24));
  [self.rootSplitView setPosition:sidebarWidth ofDividerAtIndex:0];

  CGFloat bottomHeight = MIN(260, MAX(180, self.detailSplitView.bounds.size.height * 0.28));
  CGFloat topHeight = self.detailSplitView.bounds.size.height - bottomHeight - self.detailSplitView.dividerThickness;
  [self.detailSplitView setPosition:MAX(360, topHeight) ofDividerAtIndex:0];
  self.didSetInitialSplitPositions = YES;
}

- (void)renderSidebar {
  [self clearStackView:self.sidebarStack];
  [self.sidebarStack addArrangedSubview:[self bundleHeader]];

  NSString *previousGroup = nil;
  BOOL addedBottomDivider = NO;
  for (NSDictionary *page in self.session.pages) {
    NSString *pageID = [self string:page[@"id"]];
    if (!addedBottomDivider && ([pageID isEqualToString:@"library"] || [pageID isEqualToString:@"settings"])) {
      NSBox *divider = [[NSBox alloc] init];
      divider.boxType = NSBoxSeparator;
      [self.sidebarStack addArrangedSubview:divider];
      addedBottomDivider = YES;
    }
    NSString *group = [self string:page[@"sidebarGroup"]];
    if (group.length > 0 && ![group isEqualToString:previousGroup]) {
      NSTextField *groupLabel = [self label:group.uppercaseString font:[NSFont systemFontOfSize:10 weight:NSFontWeightSemibold] textColor:NSColor.secondaryLabelColor];
      [self.sidebarStack addArrangedSubview:groupLabel];
      previousGroup = group;
    }

    NSButton *button = [NSButton buttonWithTitle:[self string:page[@"title"]] target:self action:@selector(selectPage:)];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.alignment = NSTextAlignmentLeft;
    button.controlSize = NSControlSizeLarge;
    if ([pageID isEqualToString:self.session.selectedPageID]) {
      button.bezelColor = NSColor.controlAccentColor;
      button.contentTintColor = NSColor.whiteColor;
    }
    button.toolTip = [self string:page[@"summary"]];
    objc_setAssociatedObject(button, GFCControlInfoKey, pageID, OBJC_ASSOCIATION_COPY_NONATOMIC);
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
  [self clearStackView:self.pageStack];
  [self.actionButtons removeAllObjects];
  [self.tableControllers removeAllObjects];
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
  NSStackView *stack = [self verticalStackWithSpacing:14];
  stack.alignment = NSLayoutAttributeWidth;
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
  return [self cardViewWithContent:stack];
}

- (NSView *)outputPane {
  NSStackView *stack = [self verticalStackWithSpacing:8];
  stack.alignment = NSLayoutAttributeWidth;
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

- (NSView *)cardViewWithContent:(NSView *)content {
  NSView *card = [[NSView alloc] init];
  card.wantsLayer = YES;
  card.layer.cornerRadius = 10;
  card.layer.borderWidth = 1;
  card.layer.borderColor = NSColor.separatorColor.CGColor;
  card.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

  content.translatesAutoresizingMaskIntoConstraints = NO;
  [card addSubview:content];
  [NSLayoutConstraint activateConstraints:@[
    [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
    [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
    [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
    [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18]
  ]];
  return card;
}

- (void)clearStackView:(NSStackView *)stackView {
  for (NSView *view in stackView.arrangedSubviews.copy) {
    [stackView removeArrangedSubview:view];
    [view removeFromSuperview];
  }
}

- (NSScrollView *)scrollView {
  NSScrollView *scroll = [[NSScrollView alloc] init];
  scroll.hasVerticalScroller = YES;
  scroll.hasHorizontalScroller = NO;
  scroll.autohidesScrollers = YES;
  return scroll;
}

- (void)installDocumentView:(NSView *)documentView inScrollView:(NSScrollView *)scrollView {
  documentView.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.documentView = documentView;
  NSClipView *clipView = scrollView.contentView;
  [NSLayoutConstraint activateConstraints:@[
    [documentView.leadingAnchor constraintEqualToAnchor:clipView.leadingAnchor],
    [documentView.trailingAnchor constraintEqualToAnchor:clipView.trailingAnchor],
    [documentView.topAnchor constraintEqualToAnchor:clipView.topAnchor],
    [documentView.widthAnchor constraintEqualToAnchor:clipView.widthAnchor]
  ]];
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
