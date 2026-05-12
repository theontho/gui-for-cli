#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GFCRendering : NSObject

+ (NSArray<NSDictionary *> *)allControlsInManifest:(NSDictionary *)manifest;
+ (NSDictionary<NSString *, NSString *> *)contextWithFieldValues:(NSDictionary<NSString *, NSString *> *)fieldValues
                                                    configValues:(NSDictionary<NSString *, NSString *> *)configValues
                                                  checkedOptions:(NSDictionary<NSString *, NSSet<NSString *> *> *)checkedOptions
                                                dataSourceValues:(NSDictionary<NSString *, NSString *> *)dataSourceValues
                                                      bundleRoot:(NSString *)bundleRoot
                                                 bundleWorkspace:(NSString *)bundleWorkspace;
+ (NSDictionary<NSString *, NSString *> *)contextByAddingRowValues:(NSDictionary *)row
                                                         toContext:(NSDictionary<NSString *, NSString *> *)context;
+ (NSString *)interpolate:(nullable NSString *)value context:(NSDictionary<NSString *, NSString *> *)context;
+ (NSDictionary *)renderedCommand:(NSDictionary *)command context:(NSDictionary<NSString *, NSString *> *)context;
+ (NSArray<NSString *> *)missingPlaceholdersInCommand:(NSDictionary *)command context:(NSDictionary<NSString *, NSString *> *)context;
+ (NSString *)displayCommand:(NSDictionary *)command context:(NSDictionary<NSString *, NSString *> *)context;
+ (BOOL)actionIsVisible:(NSDictionary *)action context:(NSDictionary<NSString *, NSString *> *)context;
+ (nullable NSString *)disabledReasonForAction:(NSDictionary *)action context:(NSDictionary<NSString *, NSString *> *)context;
+ (NSArray<NSDictionary *> *)hydratedRowsForControl:(NSDictionary *)control;
+ (NSString *)configKeyForControlID:(NSString *)controlID setting:(NSDictionary *)setting;
+ (NSString *)settingStorageKey:(NSDictionary *)setting;
+ (NSArray<NSString *> *)placeholdersInString:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
