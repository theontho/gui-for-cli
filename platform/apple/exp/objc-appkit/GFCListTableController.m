#import "GFCListTableController.h"
#import "GFCAppViewController+Private.h"
#import "GFCRendering.h"

#import <objc/runtime.h>

@interface GFCListTableController ()

@property(nonatomic, strong) NSDictionary *control;
@property(nonatomic, strong) NSArray<NSDictionary *> *rows;
@property(nonatomic, strong) NSDictionary<NSString *, NSString *> *renderContext;
@property(nonatomic, weak) id target;
@property(nonatomic) SEL actionSelector;
@property(nonatomic, weak) NSMutableArray<NSButton *> *actionButtons;

@end

@implementation GFCListTableController

- (instancetype)initWithControl:(NSDictionary *)control
                           rows:(NSArray<NSDictionary *> *)rows
                  renderContext:(NSDictionary<NSString *, NSString *> *)renderContext
                         target:(id)target
                 actionSelector:(SEL)actionSelector
                  actionButtons:(NSMutableArray<NSButton *> *)actionButtons {
  self = [super init];
  if (self != nil) {
    _control = control;
    _rows = rows;
    _renderContext = renderContext;
    _target = target;
    _actionSelector = actionSelector;
    _actionButtons = actionButtons;
  }
  return self;
}

- (NSScrollView *)makeTableScrollView {
  NSTableView *table = [[NSTableView alloc] init];
  table.delegate = self;
  table.dataSource = self;
  table.usesAlternatingRowBackgroundColors = YES;
  table.rowHeight = 46;
  table.headerView = [[NSTableHeaderView alloc] init];
  table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
  table.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
  table.allowsColumnResizing = YES;
  table.allowsEmptySelection = YES;
  table.style = NSTableViewStyleInset;

  NSArray *columns = [self array:self.control[@"columns"]];
  for (NSDictionary *column in columns) {
    NSString *identifier = [self string:column[@"id"]];
    NSTableColumn *tableColumn = [[NSTableColumn alloc] initWithIdentifier:identifier];
    tableColumn.title = [self string:column[@"title"]];
    tableColumn.minWidth = [identifier isEqualToString:@"name"] ? 180 : 90;
    tableColumn.width = [identifier isEqualToString:@"name"] ? 300 : 130;
    [table addTableColumn:tableColumn];
  }

  if ([self array:self.control[@"rowActions"]].count > 0) {
    NSTableColumn *actions = [[NSTableColumn alloc] initWithIdentifier:@"__actions"];
    actions.title = @"Actions";
    actions.minWidth = 150;
    actions.width = 210;
    actions.resizingMask = NSTableColumnNoResizing;
    [table addTableColumn:actions];
  }

  NSScrollView *scroll = [[NSScrollView alloc] init];
  scroll.hasVerticalScroller = YES;
  scroll.hasHorizontalScroller = YES;
  scroll.autohidesScrollers = YES;
  scroll.borderType = NSBezelBorder;
  scroll.documentView = table;
  CGFloat height = MIN(460, MAX(180, (CGFloat)self.rows.count * table.rowHeight + 34));
  [scroll.heightAnchor constraintEqualToConstant:height].active = YES;
  return scroll;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return (NSInteger)self.rows.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex {
  if (rowIndex < 0 || rowIndex >= (NSInteger)self.rows.count) {
    return [[NSView alloc] init];
  }
  NSDictionary *row = self.rows[(NSUInteger)rowIndex];
  NSString *identifier = tableColumn.identifier;
  if ([identifier isEqualToString:@"__actions"]) {
    return [self actionsViewForRow:row];
  }
  return [self cellViewForColumnID:identifier row:row];
}

- (NSView *)cellViewForColumnID:(NSString *)columnID row:(NSDictionary *)row {
  NSStackView *stack = [self verticalStackWithSpacing:3];
  stack.edgeInsets = NSEdgeInsetsMake(5, 6, 5, 6);
  NSDictionary *values = [row[@"values"] isKindOfClass:NSDictionary.class] ? row[@"values"] : @{};
  NSString *text = [self displayValueForColumnID:columnID row:row values:values];
  NSTextField *primary = [NSTextField labelWithString:text];
  primary.lineBreakMode = NSLineBreakByTruncatingMiddle;
  primary.maximumNumberOfLines = 1;
  primary.font = [columnID isEqualToString:@"name"] ? [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightMedium] : [NSFont systemFontOfSize:NSFont.systemFontSize];
  [stack addArrangedSubview:primary];

  if ([columnID isEqualToString:@"name"]) {
    NSStackView *tags = [self horizontalStackWithSpacing:4];
    NSString *status = [self string:row[@"status"]];
    if (status.length > 0) {
      [tags addArrangedSubview:[self tagLabel:[self titleForStatus:status] color:[self colorForStatus:status]]];
    }
    for (NSDictionary *tag in [self array:row[@"tags"]]) {
      NSString *title = [self string:tag[@"title"]];
      if (title.length > 0) {
        [tags addArrangedSubview:[self tagLabel:title color:NSColor.controlAccentColor]];
      }
    }
    if (tags.arrangedSubviews.count > 0) {
      [stack addArrangedSubview:tags];
    }
  } else if ([columnID isEqualToString:@"build"] && text.length > 0) {
    primary.textColor = [self colorForBuild:text];
  }

  NSString *tooltip = [self string:row[@"tooltip"]];
  if (tooltip.length > 0) {
    stack.toolTip = tooltip;
  }
  return stack;
}

- (NSView *)actionsViewForRow:(NSDictionary *)row {
  NSStackView *stack = [self horizontalStackWithSpacing:6];
  stack.edgeInsets = NSEdgeInsetsMake(5, 6, 5, 6);
  NSDictionary *buttonContext = [GFCRendering contextByAddingRowValues:row toContext:self.renderContext];
  for (NSDictionary *action in [self array:self.control[@"rowActions"]]) {
    if (![GFCRendering actionIsVisible:action context:buttonContext]) {
      continue;
    }
    NSButton *button = [NSButton buttonWithTitle:[self actionTitle:action] target:self.target action:self.actionSelector];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.controlSize = NSControlSizeSmall;
    NSArray *missing = [GFCRendering missingPlaceholdersInCommand:action[@"command"] context:buttonContext];
    NSString *disabledReason = [GFCRendering disabledReasonForAction:action context:buttonContext];
    button.enabled = missing.count == 0 && disabledReason == nil;
    button.toolTip = missing.count > 0 ? [NSString stringWithFormat:@"Required: %@", [missing componentsJoinedByString:@", "]] : (disabledReason ?: [self string:action[@"tooltip"]]);
    objc_setAssociatedObject(button, GFCControlInfoKey, @{@"action": action, @"row": row}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.actionButtons addObject:button];
    [stack addArrangedSubview:button];
  }
  if (stack.arrangedSubviews.count == 0) {
    NSTextField *label = [NSTextField labelWithString:@"-"];
    label.textColor = NSColor.tertiaryLabelColor;
    [stack addArrangedSubview:label];
  }
  return stack;
}

- (NSString *)displayValueForColumnID:(NSString *)columnID row:(NSDictionary *)row values:(NSDictionary *)values {
  if ([columnID isEqualToString:@"name"]) {
    NSString *title = [self string:row[@"title"]];
    return title.length > 0 ? title : [self string:values[columnID]];
  }
  if ([columnID isEqualToString:@"status"]) {
    NSString *status = [self string:row[@"status"]];
    return status.length > 0 ? [self titleForStatus:status] : [self string:values[columnID]];
  }
  return [self string:values[columnID]];
}

- (NSString *)actionTitle:(NSDictionary *)action {
  NSString *title = [self string:action[@"title"]];
  return title;
}

- (NSTextField *)tagLabel:(NSString *)text color:(NSColor *)color {
  NSTextField *label = [NSTextField labelWithString:text.uppercaseString];
  label.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
  label.textColor = color;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  return label;
}

- (NSString *)titleForStatus:(NSString *)status {
  if ([status caseInsensitiveCompare:@"installed"] == NSOrderedSame) {
    return @"Installed";
  }
  if ([status caseInsensitiveCompare:@"unindexed"] == NSOrderedSame) {
    return @"Unindexed";
  }
  if ([status caseInsensitiveCompare:@"incomplete"] == NSOrderedSame) {
    return @"Incomplete";
  }
  if ([status caseInsensitiveCompare:@"missing"] == NSOrderedSame) {
    return @"Missing";
  }
  return status;
}

- (NSColor *)colorForStatus:(NSString *)status {
  NSString *lower = status.lowercaseString;
  if ([lower isEqualToString:@"installed"]) {
    return NSColor.systemGreenColor;
  }
  if ([lower isEqualToString:@"unindexed"] || [lower isEqualToString:@"incomplete"]) {
    return NSColor.systemOrangeColor;
  }
  if ([lower isEqualToString:@"missing"]) {
    return NSColor.secondaryLabelColor;
  }
  return NSColor.controlAccentColor;
}

- (NSColor *)colorForBuild:(NSString *)build {
  NSString *lower = build.lowercaseString;
  if ([lower containsString:@"grch38"] || [lower containsString:@"hg38"]) {
    return NSColor.systemGreenColor;
  }
  if ([lower containsString:@"grch37"] || [lower containsString:@"hg19"]) {
    return NSColor.controlAccentColor;
  }
  if ([lower containsString:@"t2t"] || [lower containsString:@"chm13"]) {
    return NSColor.systemOrangeColor;
  }
  return NSColor.labelColor;
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
