#import "GFCAppViewController+Private.h"
#import "GFCBundleSession.h"
#import "GFCProcessRunner.h"
#import "GFCRendering.h"
#import <objc/runtime.h>

@implementation GFCAppViewController (Actions)

- (NSButton *)actionButton:(NSDictionary *)action {
  NSButton *button = [NSButton buttonWithTitle:[self string:action[@"title"]] target:self action:@selector(runAction:)];
  button.bezelStyle = NSBezelStyleRounded;
  button.toolTip = [self string:action[@"tooltip"]];
  objc_setAssociatedObject(button, GFCControlInfoKey, action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [self.actionButtons addObject:button];
  return button;
}

- (NSView *)appearanceSection {
  NSBox *box = [[NSBox alloc] init];
  box.boxType = NSBoxCustom;
  box.cornerRadius = 8;
  box.borderColor = NSColor.separatorColor;
  box.fillColor = NSColor.controlBackgroundColor;
  box.contentViewMargins = NSMakeSize(16, 16);
  NSStackView *stack = [self verticalStackWithSpacing:10];
  [stack addArrangedSubview:[self label:@"Appearance" font:[NSFont boldSystemFontOfSize:17] textColor:NSColor.labelColor]];
  [stack addArrangedSubview:[self wrappingLabel:@"This Objective-C AppKit build uses the system appearance and the bundle's default localization." font:[NSFont systemFontOfSize:NSFont.systemFontSize] textColor:NSColor.secondaryLabelColor]];
  box.contentView = stack;
  return box;
}

- (NSView *)setupSection {
  NSBox *box = [[NSBox alloc] init];
  box.boxType = NSBoxCustom;
  box.cornerRadius = 8;
  box.borderColor = NSColor.separatorColor;
  box.fillColor = NSColor.controlBackgroundColor;
  box.contentViewMargins = NSMakeSize(16, 16);
  NSStackView *stack = [self verticalStackWithSpacing:10];
  [stack addArrangedSubview:[self label:[self setupTitle] font:[NSFont boldSystemFontOfSize:17] textColor:NSColor.labelColor]];
  for (NSDictionary *step in [self array:[self dictionary:self.session.manifest[@"setup"]][@"steps"]]) {
    [stack addArrangedSubview:[self wrappingLabel:[NSString stringWithFormat:@"%@: %@", [self string:step[@"label"]], [self setupStatusForStep:step]] font:[NSFont systemFontOfSize:NSFont.systemFontSize] textColor:NSColor.labelColor]];
  }
  NSButton *runSetup = [NSButton buttonWithTitle:@"Run setup" target:self action:@selector(runSetup:)];
  runSetup.bezelStyle = NSBezelStyleRounded;
  runSetup.enabled = [self array:[self dictionary:self.session.manifest[@"setup"]][@"steps"]].count > 0;
  [stack addArrangedSubview:runSetup];
  box.contentView = stack;
  return box;
}

- (void)runAction:(NSButton *)sender {
  NSDictionary *payload = objc_getAssociatedObject(sender, GFCControlInfoKey);
  NSDictionary *action = [payload[@"action"] isKindOfClass:NSDictionary.class] ? payload[@"action"] : payload;
  NSDictionary *row = [payload[@"row"] isKindOfClass:NSDictionary.class] ? payload[@"row"] : nil;
  NSDictionary *context = [self.session renderContext];
  if (row != nil) {
    context = [GFCRendering contextByAddingRowValues:row toContext:context];
  }
  NSArray *missing = [GFCRendering missingPlaceholdersInCommand:action[@"command"] context:context];
  if (missing.count > 0) {
    [self appendOutput:[NSString stringWithFormat:@"Cannot run %@. Missing: %@", [self string:action[@"title"]], [missing componentsJoinedByString:@", "]]];
    return;
  }
  NSDictionary *rendered = [GFCRendering renderedCommand:action[@"command"] context:context];
  [self appendOutput:[NSString stringWithFormat:@"> %@", [GFCRendering displayCommand:action[@"command"] context:context]]];
  [GFCProcessRunner runExecutable:[self string:rendered[@"executable"]]
                         arguments:[self array:rendered[@"arguments"]]
                  workingDirectory:self.session.bundleRootURL.path
                       environment:[self processEnvironment]
                        completion:^(NSString *output, int exitCode, NSError *error) {
    if (error != nil) {
      [self appendOutput:[NSString stringWithFormat:@"Action failed: %@", error.localizedDescription]];
      return;
    }
    [self appendOutput:output];
    [self appendOutput:[NSString stringWithFormat:@"Exit code: %d", exitCode]];
    [self.session reloadDataSources];
    [self renderSelectedPage];
  }];
}

- (void)runSetup:(NSButton *)sender {
  NSArray *steps = [self array:[self dictionary:self.session.manifest[@"setup"]][@"steps"]];
  if (steps.count == 0) {
    return;
  }
  [self appendOutput:@"Running setup..."];
  [self runSetupSteps:steps index:0 results:[NSMutableArray array]];
}

- (void)runSetupSteps:(NSArray<NSDictionary *> *)steps index:(NSUInteger)index results:(NSMutableArray<NSDictionary *> *)results {
  if (index >= steps.count) {
    BOOL failed = NO;
    for (NSDictionary *result in results) {
      if ([[self string:result[@"status"]] isEqualToString:@"failed"]) {
        failed = YES;
      }
    }
    self.session.setupRun = @{@"status": failed ? @"failed" : @"ok", @"results": results, @"completedAt": NSDate.date.description};
    [self.session saveState];
    [self renderSelectedPage];
    return;
  }

  NSDictionary *step = steps[index];
  NSDictionary *command = [self setupCommandForStep:step];
  if (command == nil) {
    [results addObject:[self setupResultForStep:step status:@"skipped" exitCode:nil]];
    [self runSetupSteps:steps index:index + 1 results:results];
    return;
  }
  [self appendOutput:[NSString stringWithFormat:@"> %@: %@ %@", [self string:step[@"label"]], [self string:command[@"executable"]], [[self array:command[@"arguments"]] componentsJoinedByString:@" "]]];
  [GFCProcessRunner runExecutable:[self string:command[@"executable"]]
                         arguments:[self array:command[@"arguments"]]
                  workingDirectory:self.session.bundleRootURL.path
                       environment:[self processEnvironmentWithStep:step]
                        completion:^(NSString *output, int exitCode, NSError *error) {
    [self appendOutput:output];
    BOOL optional = [step[@"optional"] respondsToSelector:@selector(boolValue)] && [step[@"optional"] boolValue];
    NSString *status = (error == nil && exitCode == 0) || optional ? @"ok" : @"failed";
    if (error != nil) {
      [self appendOutput:[NSString stringWithFormat:@"Setup failed: %@", error.localizedDescription]];
    }
    [results addObject:[self setupResultForStep:step status:status exitCode:@(exitCode)]];
    if ([status isEqualToString:@"failed"]) {
      [self runSetupSteps:steps index:steps.count results:results];
    } else {
      [self runSetupSteps:steps index:index + 1 results:results];
    }
  }];
}

- (NSDictionary *)setupCommandForStep:(NSDictionary *)step {
  NSDictionary *command = [self dictionary:step[@"command"]];
  if (command.count > 0) {
    return command;
  }
  NSString *kind = [self string:step[@"kind"]];
  NSString *value = [GFCRendering interpolate:[self string:step[@"value"]] context:[self.session renderContext]];
  NSArray *arguments = [self array:step[@"arguments"]];
  if ([kind isEqualToString:@"pathTool"] && value.length > 0) {
    return @{@"executable": @"/usr/bin/env", @"arguments": @[@"which", value]};
  }
  if (([kind isEqualToString:@"setupScript"] || [kind isEqualToString:@"bundledScript"]) && value.length > 0) {
    NSString *scriptPath = [self.session.bundleRootURL.path stringByAppendingPathComponent:value];
    return @{@"executable": @"/bin/sh", @"arguments": [@[scriptPath] arrayByAddingObjectsFromArray:arguments]};
  }
  if ([kind isEqualToString:@"pixiRun"] && value.length > 0) {
    return @{@"executable": @"/usr/bin/env", @"arguments": [@[@"pixi", @"run", value] arrayByAddingObjectsFromArray:arguments]};
  }
  if ([kind isEqualToString:@"pixiInstall"]) {
    return @{@"executable": @"/usr/bin/env", @"arguments": [@[@"pixi", @"install"] arrayByAddingObjectsFromArray:arguments]};
  }
  return nil;
}

- (NSDictionary *)setupResultForStep:(NSDictionary *)step status:(NSString *)status exitCode:(NSNumber *)exitCode {
  NSMutableDictionary *result = [@{
    @"id": [self string:step[@"id"]],
    @"label": [self string:step[@"label"]],
    @"kind": [self string:step[@"kind"]],
    @"status": status
  } mutableCopy];
  if (exitCode != nil) {
    result[@"exitCode"] = exitCode;
  }
  return result;
}

- (NSString *)setupTitle {
  NSString *status = [self string:self.session.setupRun[@"status"]];
  if ([status isEqualToString:@"ok"]) {
    return @"Setup ready";
  }
  if ([status isEqualToString:@"failed"]) {
    return @"Setup needs attention";
  }
  return @"Setup not run";
}

- (NSString *)setupStatusForStep:(NSDictionary *)step {
  for (NSDictionary *result in [self array:self.session.setupRun[@"results"]]) {
    if ([[self string:result[@"id"]] isEqualToString:[self string:step[@"id"]]]) {
      return [self string:result[@"status"]];
    }
  }
  return @"not run";
}

- (void)refreshActionButtons {
  NSDictionary *context = [self.session renderContext];
  for (NSButton *button in self.actionButtons) {
    NSDictionary *payload = objc_getAssociatedObject(button, GFCControlInfoKey);
    NSDictionary *action = [payload[@"action"] isKindOfClass:NSDictionary.class] ? payload[@"action"] : payload;
    NSDictionary *row = [payload[@"row"] isKindOfClass:NSDictionary.class] ? payload[@"row"] : nil;
    NSDictionary *buttonContext = row == nil ? context : [GFCRendering contextByAddingRowValues:row toContext:context];
    NSArray *missing = [GFCRendering missingPlaceholdersInCommand:action[@"command"] context:buttonContext];
    NSString *disabledReason = [GFCRendering disabledReasonForAction:action context:buttonContext];
    BOOL visible = [GFCRendering actionIsVisible:action context:buttonContext];
    button.hidden = !visible;
    button.enabled = visible && missing.count == 0 && disabledReason == nil;
    button.toolTip = missing.count > 0 ? [NSString stringWithFormat:@"Required: %@", [missing componentsJoinedByString:@", "]] : (disabledReason ?: [self string:action[@"tooltip"]]);
  }
}

- (NSDictionary<NSString *, NSString *> *)processEnvironment {
  return @{
    @"GUI_FOR_CLI_BUNDLE_ROOT": self.session.bundleRootURL.path,
    @"GUI_FOR_CLI_BUNDLE_WORKSPACE": self.session.bundleWorkspaceURL.path
  };
}

- (NSDictionary<NSString *, NSString *> *)processEnvironmentWithStep:(NSDictionary *)step {
  NSMutableDictionary *environment = [[self processEnvironment] mutableCopy];
  NSDictionary *stepEnvironment = [step[@"environment"] isKindOfClass:NSDictionary.class] ? step[@"environment"] : @{};
  [stepEnvironment enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
    environment[[self string:key]] = [GFCRendering interpolate:[self string:obj] context:[self.session renderContext]];
  }];
  return environment;
}

@end
