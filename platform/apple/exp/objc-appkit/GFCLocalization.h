#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GFCLocalization : NSObject

+ (NSDictionary<NSString *, NSString *> *)loadStringTableWithRepoRoot:(nullable NSURL *)repoRoot
                                                           bundleRoot:(NSURL *)bundleRoot
                                                             manifest:(NSDictionary *)manifest;
+ (id)localizedObject:(id)object table:(NSDictionary<NSString *, NSString *> *)table;

@end

NS_ASSUME_NONNULL_END
