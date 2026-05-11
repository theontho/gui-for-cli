#import "GFCAppViewController+Private.h"
#import "GFCBundleSession.h"
#import "GFCListTableController.h"
#import "GFCRendering.h"
#import <objc/runtime.h>

@implementation GFCAppViewController (Controls)

- (NSView *)controlView:(NSDictionary *)control {
  NSString *kind = [self string:control[@"kind"]];
  if ([kind isEqualToString:@"text"]) {
    return [self textControl:control path:NO configKey:nil];
  }
  if ([kind isEqualToString:@"path"]) {
    return [self textControl:control path:YES configKey:nil];
  }
  if ([kind isEqualToString:@"dropdown"]) {
    return [self dropdownControl:control];
  }
  if ([kind isEqualToString:@"toggle"]) {
    return [self toggleControl:control];
  }
  if ([kind isEqualToString:@"checkboxGroup"]) {
    return [self checkboxGroupControl:control];
  }
  if ([kind isEqualToString:@"libraryList"]) {
    return [self libraryTableControl:control];
  }
  if ([kind isEqualToString:@"infoGrid"]) {
    return [self rowsControl:control];
  }
  if ([kind isEqualToString:@"configEditor"]) {
    return [self configEditorControl:control];
  }
  return [self wrappingLabel:[NSString stringWithFormat:@"Unsupported control kind: %@", kind] font:[NSFont systemFontOfSize:NSFont.systemFontSize] textColor:NSColor.secondaryLabelColor];
}

- (NSView *)textControl:(NSDictionary *)control path:(BOOL)isPath configKey:(NSString *)configKey {
  NSStackView *stack = [self verticalStackWithSpacing:5];
  stack.alignment = NSLayoutAttributeWidth;
  NSString *label = [self string:control[@"label"]];
  [stack addArrangedSubview:[self label:label font:[NSFont boldSystemFontOfSize:13] textColor:NSColor.labelColor]];
  NSString *tooltip = [self string:control[@"tooltip"]];
  if (tooltip.length > 0) {
    [stack addArrangedSubview:[self wrappingLabel:tooltip font:[NSFont systemFontOfSize:NSFont.smallSystemFontSize] textColor:NSColor.secondaryLabelColor]];
  }

  NSTextField *field = [[NSTextField alloc] init];
  field.placeholderString = [self string:control[@"placeholder"]];
  field.delegate = self;
  field.toolTip = tooltip;
  NSString *controlID = [self string:control[@"id"]];
  field.stringValue = configKey != nil ? (self.session.configValues[configKey] ?: @"") : (self.session.fieldValues[controlID] ?: @"");
  objc_setAssociatedObject(field, GFCControlInfoKey, @{@"id": controlID, @"configKey": configKey ?: @""}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  if (isPath) {
    NSStackView *row = [self horizontalStackWithSpacing:8];
    row.alignment = NSLayoutAttributeCenterY;
    [row addArrangedSubview:field];
    [field.widthAnchor constraintGreaterThanOrEqualToConstant:260].active = YES;
    NSButton *choose = [NSButton buttonWithTitle:@"Choose..." target:self action:@selector(choosePath:)];
    choose.bezelStyle = NSBezelStyleRounded;
    objc_setAssociatedObject(choose, GFCControlInfoKey, field, OBJC_ASSOCIATION_ASSIGN);
    [row addArrangedSubview:choose];
    [stack addArrangedSubview:row];
  } else {
    [stack addArrangedSubview:field];
  }
  return stack;
}

- (NSView *)dropdownControl:(NSDictionary *)control {
  NSStackView *stack = [self verticalStackWithSpacing:5];
  stack.alignment = NSLayoutAttributeWidth;
  [stack addArrangedSubview:[self label:[self string:control[@"label"]] font:[NSFont boldSystemFontOfSize:13] textColor:NSColor.labelColor]];
  NSPopUpButton *popup = [[NSPopUpButton alloc] init];
  popup.target = self;
  popup.action = @selector(popupChanged:);
  NSString *controlID = [self string:control[@"id"]];
  NSString *selected = self.session.fieldValues[controlID] ?: [self string:control[@"value"]];
  for (NSDictionary *option in [self array:control[@"options"]]) {
    [popup addItemWithTitle:[self string:option[@"title"]]];
    popup.lastItem.representedObject = [self string:option[@"id"]];
    if ([popup.lastItem.representedObject isEqualToString:selected] || (selected.length == 0 && [option[@"selected"] boolValue])) {
      [popup selectItem:popup.lastItem];
      self.session.fieldValues[controlID] = popup.lastItem.representedObject;
    }
  }
  objc_setAssociatedObject(popup, GFCControlInfoKey, controlID, OBJC_ASSOCIATION_COPY_NONATOMIC);
  [stack addArrangedSubview:popup];
  return stack;
}

- (NSView *)toggleControl:(NSDictionary *)control {
  NSButton *button = [NSButton checkboxWithTitle:[self string:control[@"label"]] target:self action:@selector(toggleChanged:)];
  NSString *controlID = [self string:control[@"id"]];
  NSString *value = self.session.fieldValues[controlID] ?: [self string:control[@"value"]];
  button.state = [value caseInsensitiveCompare:@"true"] == NSOrderedSame ? NSControlStateValueOn : NSControlStateValueOff;
  button.toolTip = [self string:control[@"tooltip"]];
  objc_setAssociatedObject(button, GFCControlInfoKey, controlID, OBJC_ASSOCIATION_COPY_NONATOMIC);
  return button;
}

- (NSView *)checkboxGroupControl:(NSDictionary *)control {
  NSStackView *stack = [self verticalStackWithSpacing:6];
  stack.alignment = NSLayoutAttributeLeading;
  NSString *controlID = [self string:control[@"id"]];
  [stack addArrangedSubview:[self label:[self string:control[@"label"]] font:[NSFont boldSystemFontOfSize:13] textColor:NSColor.labelColor]];
  NSMutableSet<NSString *> *selected = self.session.checkedOptions[controlID] ?: [NSMutableSet set];
  self.session.checkedOptions[controlID] = selected;
  for (NSDictionary *option in [self array:control[@"options"]]) {
    NSString *optionID = [self string:option[@"id"]];
    NSButton *button = [NSButton checkboxWithTitle:[self string:option[@"title"]] target:self action:@selector(checkboxChanged:)];
    button.state = [selected containsObject:optionID] ? NSControlStateValueOn : NSControlStateValueOff;
    objc_setAssociatedObject(button, GFCControlInfoKey, @{@"controlID": controlID, @"optionID": optionID}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [stack addArrangedSubview:button];
  }
  return stack;
}

- (NSView *)rowsControl:(NSDictionary *)control {
  NSStackView *stack = [self verticalStackWithSpacing:8];
  stack.alignment = NSLayoutAttributeWidth;
  [stack addArrangedSubview:[self label:[self string:control[@"label"]] font:[NSFont boldSystemFontOfSize:13] textColor:NSColor.labelColor]];
  for (NSDictionary *row in [GFCRendering hydratedRowsForControl:control]) {
    NSStackView *rowStack = [self verticalStackWithSpacing:4];
    rowStack.edgeInsets = NSEdgeInsetsMake(4, 0, 4, 0);
    NSString *title = [self string:row[@"title"]];
    NSDictionary *values = [row[@"values"] isKindOfClass:NSDictionary.class] ? row[@"values"] : @{};
    NSString *details = values.count > 0 ? [[values allValues] componentsJoinedByString:@"  "] : [self string:row[@"status"]];
    [rowStack addArrangedSubview:[self wrappingLabel:[NSString stringWithFormat:@"%@  %@", title, details] font:[NSFont systemFontOfSize:NSFont.systemFontSize] textColor:NSColor.labelColor]];
    NSArray *rowActions = [self array:control[@"rowActions"]];
    if (rowActions.count > 0) {
      NSStackView *actions = [self horizontalStackWithSpacing:6];
      for (NSDictionary *action in rowActions) {
        [actions addArrangedSubview:[self rowActionButton:action row:row]];
      }
      [rowStack addArrangedSubview:actions];
    }
    [stack addArrangedSubview:rowStack];
  }
  return stack;
}

- (NSView *)libraryTableControl:(NSDictionary *)control {
  NSStackView *stack = [self verticalStackWithSpacing:10];
  stack.alignment = NSLayoutAttributeWidth;
  NSString *label = [self string:control[@"label"]];
  [stack addArrangedSubview:[self label:label font:[NSFont boldSystemFontOfSize:13] textColor:NSColor.labelColor]];
  NSString *tooltip = [self string:control[@"tooltip"]];
  if (tooltip.length > 0) {
    [stack addArrangedSubview:[self wrappingLabel:tooltip font:[NSFont systemFontOfSize:NSFont.smallSystemFontSize] textColor:NSColor.secondaryLabelColor]];
  }

  NSArray<NSDictionary *> *rows = [GFCRendering hydratedRowsForControl:control];
  if (rows.count == 0) {
    NSBox *emptyBox = [[NSBox alloc] init];
    emptyBox.boxType = NSBoxCustom;
    emptyBox.cornerRadius = 8;
    emptyBox.borderColor = NSColor.separatorColor;
    emptyBox.fillColor = NSColor.controlBackgroundColor;
    emptyBox.contentViewMargins = NSMakeSize(12, 12);
    NSString *message = control[@"dataSource"] != nil ? @"No library items were found for the selected reference library." : @"No library items are defined.";
    emptyBox.contentView = [self wrappingLabel:message font:[NSFont systemFontOfSize:NSFont.systemFontSize] textColor:NSColor.secondaryLabelColor];
    [stack addArrangedSubview:emptyBox];
    return stack;
  }

  GFCListTableController *tableController = [[GFCListTableController alloc] initWithControl:control
                                                                                       rows:rows
                                                                                     target:self
                                                                             actionSelector:@selector(runAction:)
                                                                              actionButtons:self.actionButtons];
  [self.tableControllers addObject:tableController];
  [stack addArrangedSubview:[tableController makeTableScrollView]];
  return stack;
}

- (NSButton *)rowActionButton:(NSDictionary *)action row:(NSDictionary *)row {
  NSButton *button = [NSButton buttonWithTitle:[self string:action[@"title"]] target:self action:@selector(runAction:)];
  button.bezelStyle = NSBezelStyleRounded;
  button.toolTip = [self string:action[@"tooltip"]];
  objc_setAssociatedObject(button, GFCControlInfoKey, @{@"action": action, @"row": row}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [self.actionButtons addObject:button];
  return button;
}

- (NSView *)configEditorControl:(NSDictionary *)control {
  NSStackView *stack = [self verticalStackWithSpacing:10];
  stack.alignment = NSLayoutAttributeWidth;
  [stack addArrangedSubview:[self label:[self string:control[@"label"]] font:[NSFont boldSystemFontOfSize:13] textColor:NSColor.labelColor]];
  NSString *controlID = [self string:control[@"id"]];
  NSDictionary *configFile = [control[@"configFile"] isKindOfClass:NSDictionary.class] ? control[@"configFile"] : nil;
  if (configFile != nil) {
    NSDictionary *pathControl = @{@"id": controlID, @"label": @"Settings file", @"placeholder": [self string:configFile[@"path"]]};
    NSString *path = self.session.configFilePaths[controlID] ?: [self string:configFile[@"path"]];
    self.session.fieldValues[controlID] = path;
    [stack addArrangedSubview:[self textControl:pathControl path:YES configKey:nil]];
  }
  for (NSDictionary *setting in [self array:control[@"settings"]]) {
    NSString *configKey = [GFCRendering configKeyForControlID:controlID setting:setting];
    NSDictionary *settingControl = @{
      @"id": [self string:setting[@"id"]],
      @"label": [self string:setting[@"label"]],
      @"placeholder": [self string:setting[@"placeholder"]],
      @"tooltip": [self string:setting[@"tooltip"]]
    };
    if ([[self string:setting[@"kind"]] isEqualToString:@"dropdown"]) {
      NSMutableDictionary *dropdown = [settingControl mutableCopy];
      dropdown[@"options"] = [self array:setting[@"options"]];
      [stack addArrangedSubview:[self dropdownControl:dropdown configKey:configKey]];
    } else {
      [stack addArrangedSubview:[self textControl:settingControl path:[[self string:setting[@"kind"]] isEqualToString:@"path"] configKey:configKey]];
    }
  }
  return stack;
}

- (NSView *)dropdownControl:(NSDictionary *)control configKey:(NSString *)configKey {
  NSStackView *stack = [self verticalStackWithSpacing:5];
  stack.alignment = NSLayoutAttributeWidth;
  [stack addArrangedSubview:[self label:[self string:control[@"label"]] font:[NSFont boldSystemFontOfSize:13] textColor:NSColor.labelColor]];
  NSPopUpButton *popup = [[NSPopUpButton alloc] init];
  popup.target = self;
  popup.action = @selector(configPopupChanged:);
  NSString *selected = self.session.configValues[configKey] ?: [self string:control[@"value"]];
  for (NSDictionary *option in [self array:control[@"options"]]) {
    [popup addItemWithTitle:[self string:option[@"title"]]];
    popup.lastItem.representedObject = [self string:option[@"id"]];
    if ([popup.lastItem.representedObject isEqualToString:selected] || (selected.length == 0 && [option[@"selected"] boolValue])) {
      [popup selectItem:popup.lastItem];
      self.session.configValues[configKey] = popup.lastItem.representedObject;
    }
  }
  objc_setAssociatedObject(popup, GFCControlInfoKey, configKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
  [stack addArrangedSubview:popup];
  return stack;
}

- (void)choosePath:(NSButton *)sender {
  NSTextField *field = objc_getAssociatedObject(sender, GFCControlInfoKey);
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = YES;
  panel.canChooseDirectories = YES;
  panel.allowsMultipleSelection = NO;
  panel.directoryURL = [self pickerStartURLForPath:field.stringValue];
  [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
    if (result == NSModalResponseOK) {
      field.stringValue = panel.URL.path ?: @"";
      [self updateTextFieldValue:field];
      [self.session reloadDataSources];
      [self renderSelectedPage];
    }
  }];
}

- (NSURL *)pickerStartURLForPath:(NSString *)path {
  NSString *expanded = [path stringByExpandingTildeInPath];
  BOOL isDirectory = NO;
  if (expanded.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:expanded isDirectory:&isDirectory]) {
    return [NSURL fileURLWithPath:isDirectory ? expanded : expanded.stringByDeletingLastPathComponent isDirectory:YES];
  }
  NSString *parent = expanded.stringByDeletingLastPathComponent;
  if (parent.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:parent isDirectory:&isDirectory] && isDirectory) {
    return [NSURL fileURLWithPath:parent isDirectory:YES];
  }
  return nil;
}

- (void)controlTextDidChange:(NSNotification *)notification {
  if ([notification.object isKindOfClass:NSTextField.class]) {
    [self updateTextFieldValue:notification.object];
  }
}

- (void)updateTextFieldValue:(NSTextField *)field {
  NSDictionary *info = objc_getAssociatedObject(field, GFCControlInfoKey);
  NSString *configKey = [self string:info[@"configKey"]];
  NSString *controlID = [self string:info[@"id"]];
  if (configKey.length > 0) {
    self.session.configValues[configKey] = field.stringValue;
    [self.session syncFieldValuesFromConfigValues];
    [self.session saveConfigFiles];
  } else if (controlID.length > 0) {
    self.session.fieldValues[controlID] = field.stringValue;
    if (self.session.configFilePaths[controlID] != nil) {
      self.session.configFilePaths[controlID] = field.stringValue;
    }
  }
  [self.session saveState];
  [self refreshActionButtons];
}

- (void)popupChanged:(NSPopUpButton *)sender {
  NSString *controlID = objc_getAssociatedObject(sender, GFCControlInfoKey);
  self.session.fieldValues[controlID] = [self string:sender.selectedItem.representedObject];
  [self.session saveState];
  [self.session reloadDataSources];
  [self renderSelectedPage];
}

- (void)configPopupChanged:(NSPopUpButton *)sender {
  NSString *configKey = objc_getAssociatedObject(sender, GFCControlInfoKey);
  self.session.configValues[configKey] = [self string:sender.selectedItem.representedObject];
  [self.session syncFieldValuesFromConfigValues];
  [self.session saveConfigFiles];
  [self.session saveState];
  [self.session reloadDataSources];
  [self renderSelectedPage];
}

- (void)toggleChanged:(NSButton *)sender {
  NSString *controlID = objc_getAssociatedObject(sender, GFCControlInfoKey);
  self.session.fieldValues[controlID] = sender.state == NSControlStateValueOn ? @"true" : @"false";
  [self.session saveState];
  [self refreshActionButtons];
}

- (void)checkboxChanged:(NSButton *)sender {
  NSDictionary *info = objc_getAssociatedObject(sender, GFCControlInfoKey);
  NSString *controlID = [self string:info[@"controlID"]];
  NSString *optionID = [self string:info[@"optionID"]];
  NSMutableSet<NSString *> *selected = self.session.checkedOptions[controlID] ?: [NSMutableSet set];
  if (sender.state == NSControlStateValueOn) {
    [selected addObject:optionID];
  } else {
    [selected removeObject:optionID];
  }
  self.session.checkedOptions[controlID] = selected;
  [self.session saveState];
  [self refreshActionButtons];
}

@end
