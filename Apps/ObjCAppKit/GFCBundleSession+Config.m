#import "GFCBundleSession+Config.h"
#import "GFCRendering.h"

@implementation GFCBundleSession (Config)

- (void)loadConfigFiles {
  for (NSDictionary *control in [GFCRendering allControlsInManifest:self.manifest]) {
    if (![[self string:control[@"kind"]] isEqualToString:@"configEditor"]) {
      continue;
    }
    NSURL *url = [self configFileURLForControl:control];
    if (url == nil) {
      continue;
    }
    NSDictionary<NSString *, NSString *> *values = [self parseFlatTomlAtURL:url];
    NSString *controlID = [self string:control[@"id"]];
    for (NSDictionary *setting in [self array:control[@"settings"]]) {
      NSString *storageKey = [GFCRendering settingStorageKey:setting];
      NSString *value = values[storageKey];
      if (value != nil) {
        self.configValues[[GFCRendering configKeyForControlID:controlID setting:setting]] = value;
      }
    }
  }
}

- (void)saveConfigFiles {
  for (NSDictionary *control in [GFCRendering allControlsInManifest:self.manifest]) {
    if (![[self string:control[@"kind"]] isEqualToString:@"configEditor"]) {
      continue;
    }
    NSURL *url = [self configFileURLForControl:control];
    if (url == nil) {
      continue;
    }
    [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *controlID = [self string:control[@"id"]];
    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    for (NSDictionary *setting in [self array:control[@"settings"]]) {
      NSString *configKey = [GFCRendering configKeyForControlID:controlID setting:setting];
      NSString *storageKey = [GFCRendering settingStorageKey:setting];
      values[storageKey] = self.configValues[configKey] ?: [self string:setting[@"value"]];
    }
    [[self serializeFlatToml:values] writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }
}

- (void)syncFieldValuesFromConfigValues {
  for (NSDictionary *control in [GFCRendering allControlsInManifest:self.manifest]) {
    if (![[self string:control[@"kind"]] isEqualToString:@"configEditor"]) {
      continue;
    }
    NSString *controlID = [self string:control[@"id"]];
    for (NSDictionary *setting in [self array:control[@"settings"]]) {
      NSString *configKey = [GFCRendering configKeyForControlID:controlID setting:setting];
      NSString *value = self.configValues[configKey];
      if (value == nil) {
        continue;
      }
      NSString *settingID = [self string:setting[@"id"]];
      NSString *storageKey = [GFCRendering settingStorageKey:setting];
      if (settingID.length > 0) {
        self.fieldValues[settingID] = value;
      }
      if (storageKey.length > 0) {
        self.fieldValues[storageKey] = value;
      }
    }
  }
}

- (NSURL *)configFileURLForControl:(NSDictionary *)control {
  NSDictionary *configFile = [control[@"configFile"] isKindOfClass:NSDictionary.class] ? control[@"configFile"] : nil;
  NSString *controlID = [self string:control[@"id"]];
  NSString *path = self.configFilePaths[controlID] ?: [self string:configFile[@"path"]];
  if (path.length == 0) {
    return nil;
  }
  path = [GFCRendering interpolate:path context:[self renderContext]];
  NSString *expanded = [path stringByExpandingTildeInPath];
  if (expanded.isAbsolutePath) {
    return [NSURL fileURLWithPath:expanded];
  }
  return [self.bundleWorkspaceURL URLByAppendingPathComponent:expanded];
}

- (NSDictionary<NSString *, NSString *> *)parseFlatTomlAtURL:(NSURL *)url {
  NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
  if (text.length == 0) {
    return @{};
  }
  NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
  for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
    NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (line.length == 0 || [line hasPrefix:@"#"]) {
      continue;
    }
    NSRange equals = [line rangeOfString:@"="];
    if (equals.location == NSNotFound) {
      continue;
    }
    NSString *key = [[[line substringToIndex:equals.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
    NSString *value = [[line substringFromIndex:equals.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    values[key] = [self unquoteTomlValue:value];
  }
  return values;
}

- (NSString *)serializeFlatToml:(NSDictionary<NSString *, NSString *> *)values {
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  for (NSString *key in [[values allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    [lines addObject:[NSString stringWithFormat:@"%@ = %@", [self tomlKey:key], [self tomlValue:values[key]]]];
  }
  return [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}

- (NSString *)unquoteTomlValue:(NSString *)value {
  if (![value hasPrefix:@"\""] || ![value hasSuffix:@"\""] || value.length < 2) {
    return value;
  }
  NSString *inner = [value substringWithRange:NSMakeRange(1, value.length - 2)];
  return [[[[inner stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\\t" withString:@"\t"] stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""] stringByReplacingOccurrencesOfString:@"\\\\" withString:@"\\"];
}

- (NSString *)tomlKey:(NSString *)key {
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
  return [key rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound ? key : [self tomlValue:key];
}

- (NSString *)tomlValue:(NSString *)value {
  NSString *base = value ?: @"";
  NSString *escaped = [[[[base stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"] stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"];
  return [NSString stringWithFormat:@"\"%@\"", escaped];
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
