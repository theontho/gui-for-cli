#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GFCBundleSession : NSObject

@property(nonatomic, readonly) NSURL *bundleRootURL;
@property(nonatomic, readonly) NSURL *bundleWorkspaceURL;
@property(nonatomic, readonly, nullable) NSURL *repoRootURL;
@property(nonatomic, strong) NSDictionary *manifest;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *fieldValues;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *configValues;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *checkedOptions;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *configFilePaths;
@property(nonatomic, copy, nullable) NSString *selectedPageID;
@property(nonatomic, strong, nullable) NSDictionary *setupRun;
@property(nonatomic, strong) NSMutableArray<NSString *> *startupMessages;

+ (nullable instancetype)loadDefaultSessionWithError:(NSError **)error;
- (void)saveState;
- (NSArray<NSDictionary *> *)pages;
- (nullable NSDictionary *)pageWithID:(nullable NSString *)pageID;
- (NSDictionary<NSString *, NSString *> *)renderContext;

@end

NS_ASSUME_NONNULL_END
