#import "GFCRendering.h"

@implementation GFCRendering

+ (NSArray<NSDictionary *> *)allControlsInManifest:(NSDictionary *)manifest {
  NSMutableArray<NSDictionary *> *controls = [NSMutableArray array];
  for (NSDictionary *page in [self array:manifest[@"pages"]]) {
    for (NSDictionary *section in [self array:page[@"sections"]]) {
      for (NSDictionary *control in [self array:section[@"controls"]]) {
        [controls addObject:control];
      }
    }
  }
  return controls;
}

+ (NSDictionary<NSString *, NSString *> *)contextWithFieldValues:(NSDictionary<NSString *, NSString *> *)fieldValues
                                                    configValues:(NSDictionary<NSString *, NSString *> *)configValues
                                                  checkedOptions:(NSDictionary<NSString *, NSSet<NSString *> *> *)checkedOptions
                                                dataSourceValues:(NSDictionary<NSString *, NSString *> *)dataSourceValues
                                                      bundleRoot:(NSString *)bundleRoot
                                                 bundleWorkspace:(NSString *)bundleWorkspace {
  NSMutableDictionary<NSString *, NSString *> *context = [NSMutableDictionary dictionary];
  context[@"bundleRoot"] = bundleRoot;
  context[@"bundleWorkspace"] = bundleWorkspace;
  context[@"home"] = NSHomeDirectory();
  [context addEntriesFromDictionary:dataSourceValues];
  [context addEntriesFromDictionary:configValues];
  [fieldValues enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
    context[key] = value ?: @"";
  }];
  [configValues enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
    context[[@"config." stringByAppendingString:key]] = value ?: @"";
  }];
  [checkedOptions enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSSet<NSString *> *values, BOOL *stop) {
    context[key] = [[[values allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
  }];
  return context;
}

+ (NSDictionary<NSString *, NSString *> *)contextByAddingRowValues:(NSDictionary *)row
                                                         toContext:(NSDictionary<NSString *, NSString *> *)context {
  NSMutableDictionary<NSString *, NSString *> *next = [context mutableCopy];
  NSDictionary *values = [row[@"values"] isKindOfClass:NSDictionary.class] ? row[@"values"] : @{};
  [values enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
    NSString *stringKey = [self string:key];
    NSString *stringValue = [self string:obj];
    next[[@"row." stringByAppendingString:stringKey]] = stringValue;
    next[stringKey] = stringValue;
  }];
  next[@"row.id"] = [self string:row[@"id"]];
  next[@"row.title"] = [self string:row[@"title"]];
  next[@"row.status"] = [self string:row[@"status"]];
  return next;
}

+ (NSString *)interpolate:(NSString *)value context:(NSDictionary<NSString *, NSString *> *)context {
  if (value.length == 0) {
    return @"";
  }
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\{\\{([^}]+)\\}\\}" options:0 error:nil];
  NSMutableString *result = [value mutableCopy];
  NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:value options:0 range:NSMakeRange(0, value.length)];
  for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
    NSString *placeholder = [[value substringWithRange:[match rangeAtIndex:1]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *replacement = context[placeholder] ?: @"";
    [result replaceCharactersInRange:match.range withString:replacement];
  }
  return result;
}

+ (NSDictionary *)renderedCommand:(NSDictionary *)command context:(NSDictionary<NSString *, NSString *> *)context {
  NSMutableArray<NSString *> *arguments = [NSMutableArray array];
  for (NSString *argument in [self array:command[@"arguments"]]) {
    [arguments addObject:[self interpolate:argument context:context]];
  }
  for (NSArray *optionalGroup in [self array:command[@"optionalArguments"]]) {
    if ([self missingPlaceholdersInValues:optionalGroup context:context].count == 0) {
      for (NSString *argument in optionalGroup) {
        [arguments addObject:[self interpolate:argument context:context]];
      }
    }
  }
  return @{
    @"executable": [self interpolate:[self string:command[@"executable"]] context:context],
    @"arguments": arguments
  };
}

+ (NSArray<NSString *> *)missingPlaceholdersInCommand:(NSDictionary *)command context:(NSDictionary<NSString *, NSString *> *)context {
  NSMutableArray *values = [NSMutableArray arrayWithObject:[self string:command[@"executable"]]];
  [values addObjectsFromArray:[self array:command[@"arguments"]]];
  return [self missingPlaceholdersInValues:values context:context];
}

+ (NSString *)displayCommand:(NSDictionary *)command context:(NSDictionary<NSString *, NSString *> *)context {
  NSDictionary *rendered = [self renderedCommand:command context:context];
  NSMutableArray<NSString *> *tokens = [NSMutableArray arrayWithObject:[self shellQuote:rendered[@"executable"]]];
  for (NSString *argument in [self array:rendered[@"arguments"]]) {
    [tokens addObject:[self shellQuote:argument]];
  }
  return [tokens componentsJoinedByString:@" "];
}

+ (BOOL)actionIsVisible:(NSDictionary *)action context:(NSDictionary<NSString *, NSString *> *)context {
  for (NSDictionary *condition in [self array:action[@"visibleWhen"]]) {
    if (![self condition:condition matchesContext:context]) {
      return NO;
    }
  }
  return YES;
}

+ (NSString *)disabledReasonForAction:(NSDictionary *)action context:(NSDictionary<NSString *, NSString *> *)context {
  for (NSDictionary *condition in [self array:action[@"disabledWhen"]]) {
    if ([self condition:condition matchesContext:context]) {
      NSString *tooltip = [self interpolate:[self string:action[@"disabledTooltip"]] context:context];
      return tooltip.length > 0 ? tooltip : @"This action is not available.";
    }
  }
  return nil;
}

+ (NSArray<NSDictionary *> *)hydratedRowsForControl:(NSDictionary *)control {
  NSArray *rows = [self array:control[@"rows"]];
  NSArray *items = [self array:control[@"items"]];
  if (items.count == 0) {
    return rows;
  }

  NSMutableArray<NSDictionary *> *hydrated = [NSMutableArray array];
  NSArray *columns = [self array:control[@"columns"]];
  NSDictionary *template = [control[@"rowTemplate"] isKindOfClass:NSDictionary.class] ? control[@"rowTemplate"] : @{};
  for (NSUInteger index = 0; index < items.count; index += 1) {
    NSDictionary *item = items[index];
    NSDictionary *values = [item[@"values"] isKindOfClass:NSDictionary.class] ? item[@"values"] : item;
    NSString *fallbackID = [self string:values[@"id"]].length > 0 ? [self string:values[@"id"]] : [NSString stringWithFormat:@"row-%lu", index + 1];
    NSMutableDictionary *rowValues = [NSMutableDictionary dictionary];
    NSDictionary *templateValues = [template[@"values"] isKindOfClass:NSDictionary.class] ? template[@"values"] : nil;
    if (templateValues != nil) {
      [templateValues enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        rowValues[key] = [self interpolateItem:[self string:value] values:values];
      }];
    } else {
      for (NSDictionary *column in columns) {
        NSString *columnID = [self string:column[@"id"]];
        rowValues[columnID] = [self string:values[columnID]];
      }
    }
    NSString *titleTemplate = [self string:template[@"title"]];
    NSString *title = titleTemplate.length > 0 ? [self interpolateItem:titleTemplate values:values] : [self string:values[@"name"]];
    [hydrated addObject:@{
      @"id": [self interpolateItem:[self string:template[@"id"]] values:values].length > 0 ? [self interpolateItem:[self string:template[@"id"]] values:values] : fallbackID,
      @"title": title.length > 0 ? title : fallbackID,
      @"status": [self interpolateItem:[self string:template[@"status"]] values:values],
      @"values": rowValues
    }];
  }
  return hydrated;
}

+ (NSString *)configKeyForControlID:(NSString *)controlID setting:(NSDictionary *)setting {
  return [NSString stringWithFormat:@"%@.%@", controlID, [self string:setting[@"id"]]];
}

+ (NSString *)settingStorageKey:(NSDictionary *)setting {
  NSString *key = [self string:setting[@"key"]];
  return key.length > 0 ? key : [self string:setting[@"id"]];
}

+ (NSArray<NSString *> *)missingPlaceholdersInValues:(NSArray *)values context:(NSDictionary<NSString *, NSString *> *)context {
  NSMutableArray<NSString *> *missing = [NSMutableArray array];
  for (NSString *value in values) {
    for (NSString *placeholder in [self placeholdersInString:value]) {
      NSString *contextValue = context[placeholder];
      if ([contextValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0 && ![missing containsObject:placeholder]) {
        [missing addObject:placeholder];
      }
    }
  }
  return missing;
}

+ (NSArray<NSString *> *)placeholdersInString:(NSString *)value {
  if (value.length == 0) {
    return @[];
  }
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\{\\{([^}]+)\\}\\}" options:0 error:nil];
  NSMutableArray<NSString *> *placeholders = [NSMutableArray array];
  NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:value options:0 range:NSMakeRange(0, value.length)];
  for (NSTextCheckingResult *match in matches) {
    NSString *placeholder = [[value substringWithRange:[match rangeAtIndex:1]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![placeholders containsObject:placeholder]) {
      [placeholders addObject:placeholder];
    }
  }
  return placeholders;
}

+ (BOOL)condition:(NSDictionary *)condition matchesContext:(NSDictionary<NSString *, NSString *> *)context {
  NSString *value = [context[[self string:condition[@"placeholder"]]] ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSNumber *exists = condition[@"exists"];
  if ([exists isKindOfClass:NSNumber.class] && exists.boolValue != (value.length > 0)) {
    return NO;
  }
  NSString *equalTo = [self optionalString:condition[@"equals"]];
  if (equalTo != nil && ![value isEqualToString:[self interpolate:equalTo context:context]]) {
    return NO;
  }
  NSString *notEquals = [self optionalString:condition[@"notEquals"]];
  if (notEquals != nil && [value isEqualToString:[self interpolate:notEquals context:context]]) {
    return NO;
  }
  NSArray *inValues = [self array:condition[@"in"]];
  if (inValues.count > 0 && ![[self interpolatedValues:inValues context:context] containsObject:value]) {
    return NO;
  }
  NSArray *notInValues = [self array:condition[@"notIn"]];
  if ([[self interpolatedValues:notInValues context:context] containsObject:value]) {
    return NO;
  }
  if (![self compareValue:value condition:condition key:@"lessThan" context:context block:^BOOL(double left, double right) { return left < right; }]) {
    return NO;
  }
  if (![self compareValue:value condition:condition key:@"lessThanOrEqual" context:context block:^BOOL(double left, double right) { return left <= right; }]) {
    return NO;
  }
  if (![self compareValue:value condition:condition key:@"greaterThan" context:context block:^BOOL(double left, double right) { return left > right; }]) {
    return NO;
  }
  if (![self compareValue:value condition:condition key:@"greaterThanOrEqual" context:context block:^BOOL(double left, double right) { return left >= right; }]) {
    return NO;
  }
  return YES;
}

+ (NSArray<NSString *> *)interpolatedValues:(NSArray *)values context:(NSDictionary<NSString *, NSString *> *)context {
  NSMutableArray<NSString *> *result = [NSMutableArray array];
  for (id value in values) {
    [result addObject:[self interpolate:[self string:value] context:context]];
  }
  return result;
}

+ (BOOL)compareValue:(NSString *)value
           condition:(NSDictionary *)condition
                 key:(NSString *)key
             context:(NSDictionary<NSString *, NSString *> *)context
               block:(BOOL (^)(double left, double right))block {
  NSString *rawRight = [self optionalString:condition[key]];
  if (rawRight == nil) {
    return YES;
  }
  double left = value.doubleValue;
  double right = [self interpolate:rawRight context:context].doubleValue;
  return block(left, right);
}

+ (NSString *)interpolateItem:(NSString *)value values:(NSDictionary *)values {
  if (value.length == 0) {
    return @"";
  }
  NSMutableDictionary<NSString *, NSString *> *context = [NSMutableDictionary dictionary];
  [values enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
    context[[self string:key]] = [self string:obj];
  }];
  return [self interpolate:value context:context];
}

+ (NSString *)shellQuote:(NSString *)value {
  if (value.length == 0) {
    return @"''";
  }
  NSCharacterSet *safe = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:-"];
  if ([value rangeOfCharacterFromSet:safe.invertedSet].location == NSNotFound) {
    return value;
  }
  return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

+ (NSArray *)array:(id)value {
  return [value isKindOfClass:NSArray.class] ? value : @[];
}

+ (NSString *)string:(id)value {
  if ([value isKindOfClass:NSString.class]) {
    return value;
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [value stringValue];
  }
  return @"";
}

+ (NSString *)optionalString:(id)value {
  NSString *string = [self string:value];
  return string.length == 0 ? nil : string;
}

@end
