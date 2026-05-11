#import "GFCBundleSession+DataSources.h"
#import "GFCRendering.h"

@implementation GFCBundleSession (DataSources)

- (void)reloadDataSources {
  self.dataSourceValues = [NSMutableDictionary dictionary];
  NSMutableDictionary *manifest = [self mutableJSONObject:self.manifest];
  for (NSMutableDictionary *page in [self array:manifest[@"pages"]]) {
    for (NSMutableDictionary *section in [self array:page[@"sections"]]) {
      [self hydrateSectionDataSource:section];
      for (NSMutableDictionary *control in [self array:section[@"controls"]]) {
        [self hydrateControlDataSource:control];
        for (NSMutableDictionary *setting in [self array:control[@"settings"]]) {
          [self hydrateConfigSettingDataSource:setting];
        }
      }
    }
  }
  self.manifest = manifest;
}

- (void)hydrateSectionDataSource:(NSMutableDictionary *)section {
  NSDictionary *dataSource = [section[@"dataSource"] isKindOfClass:NSDictionary.class] ? section[@"dataSource"] : nil;
  if (dataSource == nil) {
    return;
  }
  NSDictionary *payload = [self runDataSource:dataSource label:[self string:section[@"title"]]];
  NSDictionary *values = [payload[@"values"] isKindOfClass:NSDictionary.class] ? payload[@"values"] : @{};
  [values enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
    self.dataSourceValues[[self string:key]] = [self string:obj];
  }];
}

- (void)hydrateControlDataSource:(NSMutableDictionary *)control {
  NSDictionary *dataSource = [control[@"dataSource"] isKindOfClass:NSDictionary.class] ? control[@"dataSource"] : nil;
  if (dataSource == nil) {
    return;
  }
  NSDictionary *payload = [self runDataSource:dataSource label:[self string:control[@"label"]]];
  [self applyPayload:payload toControl:control];
}

- (void)hydrateConfigSettingDataSource:(NSMutableDictionary *)setting {
  NSDictionary *dataSource = [setting[@"dataSource"] isKindOfClass:NSDictionary.class] ? setting[@"dataSource"] : nil;
  if (dataSource == nil) {
    return;
  }
  NSDictionary *payload = [self runDataSource:dataSource label:[self string:setting[@"label"]]];
  NSArray *options = [payload[@"options"] isKindOfClass:NSArray.class] ? payload[@"options"] : nil;
  if (options != nil) {
    setting[@"options"] = options;
  }
}

- (void)applyPayload:(NSDictionary *)payload toControl:(NSMutableDictionary *)control {
  NSArray *options = [payload[@"options"] isKindOfClass:NSArray.class] ? payload[@"options"] : nil;
  NSArray *rows = [payload[@"rows"] isKindOfClass:NSArray.class] ? payload[@"rows"] : nil;
  NSArray *items = [payload[@"items"] isKindOfClass:NSArray.class] ? payload[@"items"] : nil;
  NSArray *rowActions = [payload[@"rowActions"] isKindOfClass:NSArray.class] ? payload[@"rowActions"] : payload[@"actions"];
  if (options != nil) {
    control[@"options"] = options;
  }
  if (rows != nil) {
    control[@"rows"] = rows;
    control[@"items"] = @[];
  } else if (items != nil) {
    control[@"items"] = items;
  }
  if ([rowActions isKindOfClass:NSArray.class]) {
    control[@"rowActions"] = rowActions;
  }
}

- (NSDictionary *)runDataSource:(NSDictionary *)dataSource label:(NSString *)label {
  NSString *path = [self string:dataSource[@"path"]];
  NSURL *executableURL = [self resolvedBundleURL:path mustExist:YES];
  if (executableURL == nil) {
    [self.startupMessages addObject:[NSString stringWithFormat:@"Data source failed for %@: invalid path %@", label, path]];
    return @{};
  }

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = executableURL;
  task.arguments = [self interpolatedArguments:[self array:dataSource[@"arguments"]]];
  NSString *workingDirectory = [self string:dataSource[@"workingDirectory"]];
  task.currentDirectoryURL = workingDirectory.length > 0 ? [self resolvedBundleURL:workingDirectory mustExist:NO] : self.bundleRootURL;
  NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
  [environment addEntriesFromDictionary:[self dataSourceEnvironment:dataSource]];
  task.environment = environment;

  NSPipe *stdoutPipe = [NSPipe pipe];
  NSPipe *stderrPipe = [NSPipe pipe];
  task.standardOutput = stdoutPipe;
  task.standardError = stderrPipe;
  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    [self.startupMessages addObject:[NSString stringWithFormat:@"Data source failed for %@: %@", label, launchError.localizedDescription]];
    return @{};
  }
  [task waitUntilExit];
  NSData *output = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
  NSData *errorOutput = [stderrPipe.fileHandleForReading readDataToEndOfFile];
  if (task.terminationStatus != 0) {
    NSString *message = [[NSString alloc] initWithData:errorOutput encoding:NSUTF8StringEncoding] ?: @"script failed";
    [self.startupMessages addObject:[NSString stringWithFormat:@"Data source failed for %@: %@", label, [message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]]];
    return @{};
  }
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:output options:NSJSONReadingMutableContainers error:nil];
  if (![payload isKindOfClass:NSDictionary.class]) {
    [self.startupMessages addObject:[NSString stringWithFormat:@"Data source failed for %@: invalid JSON", label]];
    return @{};
  }
  return payload;
}

- (NSDictionary<NSString *, NSString *> *)dataSourceEnvironment:(NSDictionary *)dataSource {
  NSMutableDictionary<NSString *, NSString *> *environment = [@{
    @"GUI_FOR_CLI_BUNDLE_ROOT": self.bundleRootURL.path,
    @"GUI_FOR_CLI_BUNDLE_WORKSPACE": self.bundleWorkspaceURL.path,
    @"GUI_FOR_CLI_DATA_SOURCE": @"1"
  } mutableCopy];
  [self.fieldValues enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
    environment[[@"GUI_FOR_CLI_FIELD_" stringByAppendingString:[self environmentKey:key]]] = value ?: @"";
  }];
  [self.configValues enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
    environment[[@"GUI_FOR_CLI_CONFIG_" stringByAppendingString:[self environmentKey:key]]] = value ?: @"";
  }];
  NSDictionary *custom = [dataSource[@"environment"] isKindOfClass:NSDictionary.class] ? dataSource[@"environment"] : @{};
  [custom enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
    environment[[self string:key]] = [GFCRendering interpolate:[self string:obj] context:[self renderContext]];
  }];
  return environment;
}

- (NSArray<NSString *> *)interpolatedArguments:(NSArray *)arguments {
  NSMutableArray<NSString *> *result = [NSMutableArray array];
  NSDictionary *context = [self renderContext];
  for (id argument in arguments) {
    [result addObject:[GFCRendering interpolate:[self string:argument] context:context]];
  }
  return result;
}

- (NSURL *)resolvedBundleURL:(NSString *)path mustExist:(BOOL)mustExist {
  NSString *expanded = [GFCRendering interpolate:path context:[self renderContext]];
  if (expanded.length == 0 || expanded.isAbsolutePath || [expanded containsString:@".."]) {
    return nil;
  }
  NSURL *url = [[self.bundleRootURL URLByAppendingPathComponent:expanded] URLByStandardizingPath];
  NSString *rootPath = self.bundleRootURL.URLByStandardizingPath.path;
  if (![url.path isEqualToString:rootPath] && ![url.path hasPrefix:[rootPath stringByAppendingString:@"/"]]) {
    return nil;
  }
  if (mustExist && ![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
    return nil;
  }
  return url;
}

- (NSMutableDictionary *)mutableJSONObject:(id)object {
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
  return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] ?: [NSMutableDictionary dictionary];
}

- (NSString *)environmentKey:(NSString *)value {
  NSMutableString *result = [NSMutableString string];
  for (NSUInteger index = 0; index < value.length; index += 1) {
    unichar character = [value characterAtIndex:index];
    if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:character]) {
      [result appendString:[[NSString stringWithFormat:@"%C", character] uppercaseString]];
    } else {
      [result appendString:@"_"];
    }
  }
  return result;
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
