#import "GFCBundleSession.h"
#import "GFCLocalization.h"
#import "GFCRendering.h"

@interface GFCBundleSession ()

@property(nonatomic, readwrite) NSURL *bundleRootURL;
@property(nonatomic, readwrite) NSURL *bundleWorkspaceURL;
@property(nonatomic, readwrite, nullable) NSURL *repoRootURL;

@end

@implementation GFCBundleSession

+ (instancetype)loadDefaultSessionWithError:(NSError **)error {
  NSURL *repoRoot = [self repoRootURL];
  NSURL *bundleRoot = [self defaultBundleRootWithRepoRoot:repoRoot];
  if (bundleRoot == nil) {
    if (error != nil) {
      *error = [NSError errorWithDomain:@"GUIForCLIObjCAppKit"
                                   code:1
                               userInfo:@{NSLocalizedDescriptionKey: @"Could not locate WGSExtract bundle resources."}];
    }
    return nil;
  }

  NSMutableDictionary *manifest = [[self loadManifestAtBundleRoot:bundleRoot error:error] mutableCopy];
  if (manifest == nil) {
    return nil;
  }

  NSDictionary *table = [GFCLocalization loadStringTableWithRepoRoot:repoRoot bundleRoot:bundleRoot manifest:manifest];
  manifest = [[GFCLocalization localizedObject:manifest table:table] mutableCopy];

  GFCBundleSession *session = [[GFCBundleSession alloc] init];
  session.bundleRootURL = bundleRoot;
  session.repoRootURL = repoRoot;
  session.manifest = manifest;
  session.startupMessages = [NSMutableArray array];

  NSString *bundleID = [self nonEmptyString:manifest[@"id"]] ?: @"default";
  session.bundleWorkspaceURL = [[self appSupportRoot] URLByAppendingPathComponent:[NSString stringWithFormat:@"Bundles/%@", bundleID] isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:session.bundleWorkspaceURL withIntermediateDirectories:YES attributes:nil error:nil];

  NSDictionary *state = [self loadStateAtURL:session.stateURL];
  session.selectedPageID = [self nonEmptyString:state[@"selectedPageID"]];
  session.setupRun = [state[@"setupRun"] isKindOfClass:NSDictionary.class] ? state[@"setupRun"] : nil;
  session.fieldValues = [[self initialFieldValuesForManifest:manifest state:state] mutableCopy];
  session.configValues = [[self initialConfigValuesForManifest:manifest state:state] mutableCopy];
  session.checkedOptions = [[self initialCheckedOptionsForManifest:manifest state:state] mutableCopy];
  session.configFilePaths = [[self initialConfigFilePathsForManifest:manifest state:state] mutableCopy];
  if ([session pageWithID:session.selectedPageID] == nil) {
    session.selectedPageID = [session.pages.firstObject objectForKey:@"id"];
  }
  return session;
}

- (void)saveState {
  NSMutableDictionary *checked = [NSMutableDictionary dictionary];
  [self.checkedOptions enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSSet<NSString *> *values, BOOL *stop) {
    checked[key] = [[values allObjects] sortedArrayUsingSelector:@selector(compare:)];
  }];

  NSMutableDictionary *state = [NSMutableDictionary dictionary];
  state[@"fieldValues"] = self.fieldValues;
  state[@"configValues"] = self.configValues;
  state[@"checkedOptions"] = checked;
  state[@"configFilePaths"] = self.configFilePaths;
  if (self.selectedPageID != nil) {
    state[@"selectedPageID"] = self.selectedPageID;
  }
  if (self.setupRun != nil) {
    state[@"setupRun"] = self.setupRun;
  }

  NSData *data = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:nil];
  if (data != nil) {
    [data writeToURL:self.stateURL atomically:YES];
  }
}

- (NSArray<NSDictionary *> *)pages {
  return [self.manifest[@"pages"] isKindOfClass:NSArray.class] ? self.manifest[@"pages"] : @[];
}

- (NSDictionary *)pageWithID:(NSString *)pageID {
  if (pageID.length > 0) {
    for (NSDictionary *page in self.pages) {
      if ([[self.class nonEmptyString:page[@"id"]] isEqualToString:pageID]) {
        return page;
      }
    }
  }
  return self.pages.firstObject;
}

- (NSDictionary<NSString *, NSString *> *)renderContext {
  return [GFCRendering contextWithFieldValues:self.fieldValues
                                 configValues:self.configValues
                               checkedOptions:self.checkedOptions
                                   bundleRoot:self.bundleRootURL.path
                              bundleWorkspace:self.bundleWorkspaceURL.path];
}

- (NSURL *)stateURL {
  return [self.bundleWorkspaceURL URLByAppendingPathComponent:@"state.json"];
}

+ (NSDictionary *)loadManifestAtBundleRoot:(NSURL *)bundleRoot error:(NSError **)error {
  NSURL *manifestURL = [bundleRoot URLByAppendingPathComponent:@"manifest.json"];
  NSMutableDictionary *manifest = [[self jsonObjectAtURL:manifestURL error:error] mutableCopy];
  if (manifest == nil) {
    return nil;
  }

  NSArray *pages = [manifest[@"pages"] isKindOfClass:NSArray.class] ? manifest[@"pages"] : @[];
  BOOL splitPageFiles = pages.count > 0;
  for (id page in pages) {
    if (![page isKindOfClass:NSString.class]) {
      splitPageFiles = NO;
      break;
    }
  }

  if (splitPageFiles) {
    NSMutableArray *loadedPages = [NSMutableArray array];
    for (NSString *pageFile in pages) {
      if ([pageFile containsString:@"/"] || [pageFile containsString:@"\\"] || ![pageFile hasSuffix:@".json"]) {
        if (error != nil) {
          *error = [NSError errorWithDomain:@"GUIForCLIObjCAppKit"
                                       code:2
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid page file name: %@", pageFile]}];
        }
        return nil;
      }
      NSURL *pageURL = [[bundleRoot URLByAppendingPathComponent:@"pages" isDirectory:YES] URLByAppendingPathComponent:pageFile];
      NSDictionary *page = [self jsonObjectAtURL:pageURL error:error];
      if (page == nil) {
        return nil;
      }
      [loadedPages addObject:page];
    }
    manifest[@"pages"] = loadedPages;
  }
  return manifest;
}

+ (id)jsonObjectAtURL:(NSURL *)url error:(NSError **)error {
  NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
  if (data == nil) {
    return nil;
  }
  return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];
}

+ (NSDictionary *)loadStateAtURL:(NSURL *)url {
  NSData *data = [NSData dataWithContentsOfURL:url];
  if (data == nil) {
    return @{};
  }
  NSDictionary *state = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [state isKindOfClass:NSDictionary.class] ? state : @{};
}

+ (NSDictionary<NSString *, NSString *> *)initialFieldValuesForManifest:(NSDictionary *)manifest state:(NSDictionary *)state {
  NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
  for (NSDictionary *control in [GFCRendering allControlsInManifest:manifest]) {
    NSString *kind = [self nonEmptyString:control[@"kind"]];
    if ([self kindPersistsFieldValue:kind]) {
      values[[self nonEmptyString:control[@"id"]] ?: @""] = [self string:control[@"value"]];
    }
  }
  NSDictionary *saved = [state[@"fieldValues"] isKindOfClass:NSDictionary.class] ? state[@"fieldValues"] : @{};
  [saved enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
    if ([key isKindOfClass:NSString.class]) {
      values[key] = [self string:obj];
    }
  }];
  return values;
}

+ (NSDictionary<NSString *, NSString *> *)initialConfigValuesForManifest:(NSDictionary *)manifest state:(NSDictionary *)state {
  NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
  for (NSDictionary *control in [GFCRendering allControlsInManifest:manifest]) {
    if (![[self string:control[@"kind"]] isEqualToString:@"configEditor"]) {
      continue;
    }
    NSString *controlID = [self string:control[@"id"]];
    for (NSDictionary *setting in [self array:control[@"settings"]]) {
      values[[GFCRendering configKeyForControlID:controlID setting:setting]] = [self string:setting[@"value"]];
    }
  }
  NSDictionary *saved = [state[@"configValues"] isKindOfClass:NSDictionary.class] ? state[@"configValues"] : @{};
  [saved enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
    if ([key isKindOfClass:NSString.class]) {
      values[key] = [self string:obj];
    }
  }];
  return values;
}

+ (NSDictionary<NSString *, NSMutableSet<NSString *> *> *)initialCheckedOptionsForManifest:(NSDictionary *)manifest state:(NSDictionary *)state {
  NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *values = [NSMutableDictionary dictionary];
  for (NSDictionary *control in [GFCRendering allControlsInManifest:manifest]) {
    if (![[self string:control[@"kind"]] isEqualToString:@"checkboxGroup"]) {
      continue;
    }
    NSMutableSet<NSString *> *selected = [NSMutableSet set];
    for (NSDictionary *option in [self array:control[@"options"]]) {
      if ([option[@"selected"] respondsToSelector:@selector(boolValue)] && [option[@"selected"] boolValue]) {
        [selected addObject:[self string:option[@"id"]]];
      }
    }
    values[[self string:control[@"id"]]] = selected;
  }
  NSDictionary *saved = [state[@"checkedOptions"] isKindOfClass:NSDictionary.class] ? state[@"checkedOptions"] : @{};
  [saved enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
    if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSArray.class]) {
      values[key] = [NSMutableSet setWithArray:obj];
    }
  }];
  return values;
}

+ (NSDictionary<NSString *, NSString *> *)initialConfigFilePathsForManifest:(NSDictionary *)manifest state:(NSDictionary *)state {
  NSMutableDictionary<NSString *, NSString *> *paths = [NSMutableDictionary dictionary];
  for (NSDictionary *control in [GFCRendering allControlsInManifest:manifest]) {
    NSDictionary *configFile = [control[@"configFile"] isKindOfClass:NSDictionary.class] ? control[@"configFile"] : nil;
    if (configFile != nil) {
      paths[[self string:control[@"id"]]] = [self string:configFile[@"path"]];
    }
  }
  NSDictionary *saved = [state[@"configFilePaths"] isKindOfClass:NSDictionary.class] ? state[@"configFilePaths"] : @{};
  [saved enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
    if ([key isKindOfClass:NSString.class]) {
      paths[key] = [self string:obj];
    }
  }];
  return paths;
}

+ (BOOL)kindPersistsFieldValue:(NSString *)kind {
  return [@[@"text", @"path", @"dropdown", @"toggle"] containsObject:kind];
}

+ (NSURL *)appSupportRoot {
  NSURL *root = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
  NSURL *url = [root URLByAppendingPathComponent:@"GUI for CLI/ObjC AppKit" isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
  return url;
}

+ (NSURL *)defaultBundleRootWithRepoRoot:(NSURL *)repoRoot {
  NSString *envPath = NSProcessInfo.processInfo.environment[@"GFC_BUNDLE_PATH"];
  if (envPath.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:[envPath stringByAppendingPathComponent:@"manifest.json"]]) {
    return [NSURL fileURLWithPath:envPath isDirectory:YES];
  }

  NSArray<NSURL *> *resourceCandidates = @[
    [NSBundle.mainBundle URLForResource:@"WGSExtract" withExtension:nil subdirectory:@"DemoBundles"] ?: NSURL.new,
    [NSBundle.mainBundle URLForResource:@"WGSExtract" withExtension:nil] ?: NSURL.new
  ];
  for (NSURL *candidate in resourceCandidates) {
    if (candidate.path.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:[candidate.path stringByAppendingPathComponent:@"manifest.json"]]) {
      return candidate;
    }
  }

  NSURL *sourceCandidate = [repoRoot URLByAppendingPathComponent:@"Examples/WGSExtract" isDirectory:YES];
  if (repoRoot != nil && [NSFileManager.defaultManager fileExistsAtPath:[sourceCandidate.path stringByAppendingPathComponent:@"manifest.json"]]) {
    return sourceCandidate;
  }
  return nil;
}

+ (NSURL *)repoRootURL {
  NSString *envPath = NSProcessInfo.processInfo.environment[@"GFC_REPO_ROOT"];
  if (envPath.length > 0) {
    return [NSURL fileURLWithPath:envPath isDirectory:YES];
  }
#ifdef GFC_SOURCE_ROOT
  NSString *sourceRoot = @GFC_SOURCE_ROOT;
  if (sourceRoot.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:[sourceRoot stringByAppendingPathComponent:@"Package.swift"]]) {
    return [NSURL fileURLWithPath:sourceRoot isDirectory:YES];
  }
#endif
  NSMutableArray<NSURL *> *starts = [NSMutableArray arrayWithObject:[[NSURL fileURLWithPath:NSFileManager.defaultManager.currentDirectoryPath] URLByStandardizingPath]];
  [starts addObject:NSBundle.mainBundle.bundleURL];
  for (NSURL *start in starts) {
    NSURL *candidate = start;
    while (candidate.path.length > 1) {
      if ([NSFileManager.defaultManager fileExistsAtPath:[candidate.path stringByAppendingPathComponent:@"Package.swift"]]) {
        return candidate;
      }
      candidate = [candidate URLByDeletingLastPathComponent];
    }
  }
  return nil;
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

+ (NSString *)nonEmptyString:(id)value {
  NSString *string = [self string:value];
  NSString *trimmed = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return trimmed.length == 0 ? nil : trimmed;
}

@end
