#import "GFCBundleSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface GFCBundleSession (Config)

- (void)loadConfigFiles;
- (nullable NSURL *)configFileURLForControl:(NSDictionary *)control;

@end

NS_ASSUME_NONNULL_END
