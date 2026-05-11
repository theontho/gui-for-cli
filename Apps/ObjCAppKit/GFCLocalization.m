#import "GFCLocalization.h"

@implementation GFCLocalization

+ (NSDictionary<NSString *, NSString *> *)loadStringTableWithRepoRoot:(NSURL *)repoRoot
                                                           bundleRoot:(NSURL *)bundleRoot
                                                             manifest:(NSDictionary *)manifest {
  NSString *defaultCode = [self nonEmptyString:manifest[@"defaultLocalizationCode"]] ?: @"en";
  NSString *preferredLocale = [self nonEmptyString:[NSUserDefaults.standardUserDefaults stringForKey:@"preferredLocale"]];
  NSString *locale = [self sanitizedLocaleCode:preferredLocale] ?: defaultCode;
  NSMutableDictionary<NSString *, NSString *> *table = [NSMutableDictionary dictionary];

  if (repoRoot != nil) {
    [table addEntriesFromDictionary:[self tableAtURL:[repoRoot URLByAppendingPathComponent:@"Resources/BuiltinStrings/strings.en.toml"]]];
    if (![locale isEqualToString:@"en"]) {
      NSString *fileName = [NSString stringWithFormat:@"Resources/BuiltinStrings/strings.%@.toml", locale];
      [table addEntriesFromDictionary:[self tableAtURL:[repoRoot URLByAppendingPathComponent:fileName]]];
    }
  }

  NSString *defaultBundleStrings = [NSString stringWithFormat:@"strings/strings.%@.toml", defaultCode];
  [table addEntriesFromDictionary:[self tableAtURL:[bundleRoot URLByAppendingPathComponent:defaultBundleStrings]]];
  if (![locale isEqualToString:defaultCode]) {
    NSString *localeBundleStrings = [NSString stringWithFormat:@"strings/strings.%@.toml", locale];
    [table addEntriesFromDictionary:[self tableAtURL:[bundleRoot URLByAppendingPathComponent:localeBundleStrings]]];
  }
  return table;
}

+ (id)localizedObject:(id)object table:(NSDictionary<NSString *, NSString *> *)table {
  if ([object isKindOfClass:NSString.class]) {
    NSString *value = (NSString *)object;
    return table[value] ?: value;
  }
  if ([object isKindOfClass:NSArray.class]) {
    NSMutableArray *localized = [NSMutableArray array];
    for (id item in (NSArray *)object) {
      [localized addObject:[self localizedObject:item table:table] ?: NSNull.null];
    }
    return localized;
  }
  if ([object isKindOfClass:NSDictionary.class]) {
    NSMutableDictionary *localized = [NSMutableDictionary dictionary];
    [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
      localized[key] = [self localizedObject:value table:table] ?: NSNull.null;
    }];
    return localized;
  }
  return object;
}

+ (NSDictionary<NSString *, NSString *> *)tableAtURL:(NSURL *)url {
  NSData *data = [NSData dataWithContentsOfURL:url];
  if (data == nil) {
    return @{};
  }
  NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (text.length == 0) {
    return @{};
  }
  return [self parseTomlStrings:text];
}

+ (NSDictionary<NSString *, NSString *> *)parseTomlStrings:(NSString *)text {
  NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
  NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  NSUInteger index = 0;
  while (index < lines.count) {
    NSString *rawLine = lines[index++];
    NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (line.length == 0 || [line hasPrefix:@"#"]) {
      continue;
    }
    NSRange equals = [line rangeOfString:@"="];
    if (equals.location == NSNotFound) {
      continue;
    }

    NSString *key = [[line substringToIndex:equals.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    key = [self unquoted:key];
    NSString *rawValue = [[line substringFromIndex:equals.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([rawValue hasPrefix:@"\"\"\""]) {
      NSMutableArray<NSString *> *collected = [NSMutableArray array];
      NSString *first = [rawValue substringFromIndex:3];
      NSRange sameLineEnd = [first rangeOfString:@"\"\"\""];
      if (sameLineEnd.location != NSNotFound) {
        [collected addObject:[first substringToIndex:sameLineEnd.location]];
      } else {
        [collected addObject:first];
        while (index < lines.count) {
          NSString *nextLine = lines[index++];
          NSRange end = [nextLine rangeOfString:@"\"\"\""];
          if (end.location != NSNotFound) {
            [collected addObject:[nextLine substringToIndex:end.location]];
            break;
          }
          [collected addObject:nextLine];
        }
      }
      if (collected.count > 0 && [collected.firstObject isEqualToString:@""]) {
        [collected removeObjectAtIndex:0];
      }
      if (collected.count > 0 && [collected.lastObject isEqualToString:@""]) {
        [collected removeLastObject];
      }
      values[key] = [collected componentsJoinedByString:@"\n"];
      continue;
    }

    if (![rawValue hasPrefix:@"\""]) {
      continue;
    }
    NSUInteger closing = [self closingQuoteIndexInString:rawValue];
    if (closing == NSNotFound) {
      continue;
    }
    values[key] = [self unescape:[rawValue substringWithRange:NSMakeRange(1, closing - 1)]];
  }
  return values;
}

+ (NSUInteger)closingQuoteIndexInString:(NSString *)value {
  BOOL escaped = NO;
  for (NSUInteger index = 1; index < value.length; index += 1) {
    unichar character = [value characterAtIndex:index];
    if (escaped) {
      escaped = NO;
    } else if (character == '\\') {
      escaped = YES;
    } else if (character == '"') {
      return index;
    }
  }
  return NSNotFound;
}

+ (NSString *)unquoted:(NSString *)key {
  if ([key hasPrefix:@"\""] && [key hasSuffix:@"\""] && key.length >= 2) {
    return [self unescape:[key substringWithRange:NSMakeRange(1, key.length - 2)]];
  }
  return key;
}

+ (NSString *)unescape:(NSString *)value {
  NSMutableString *result = [NSMutableString string];
  BOOL escaped = NO;
  for (NSUInteger index = 0; index < value.length; index += 1) {
    unichar character = [value characterAtIndex:index];
    if (!escaped && character == '\\') {
      escaped = YES;
      continue;
    }
    if (escaped) {
      if (character == 'n') {
        [result appendString:@"\n"];
      } else if (character == 'r') {
        [result appendString:@"\r"];
      } else if (character == 't') {
        [result appendString:@"\t"];
      } else {
        [result appendFormat:@"%C", character];
      }
      escaped = NO;
      continue;
    }
    [result appendFormat:@"%C", character];
  }
  return result;
}

+ (nullable NSString *)nonEmptyString:(id)value {
  if (![value isKindOfClass:NSString.class]) {
    return nil;
  }
  NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return trimmed.length == 0 ? nil : trimmed;
}

+ (nullable NSString *)sanitizedLocaleCode:(NSString *)value {
  NSString *code = [self nonEmptyString:value];
  if (code == nil) {
    return nil;
  }
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
  if ([code rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) {
    return nil;
  }
  return code;
}

@end
