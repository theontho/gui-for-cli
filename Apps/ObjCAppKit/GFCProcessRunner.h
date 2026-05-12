#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^GFCProcessCompletion)(NSString *output, int exitCode, NSError *_Nullable error);

@interface GFCProcessRunner : NSObject

+ (void)runExecutable:(NSString *)executable
            arguments:(NSArray<NSString *> *)arguments
     workingDirectory:(NSString *)workingDirectory
          environment:(NSDictionary<NSString *, NSString *> *)environment
           completion:(GFCProcessCompletion)completion;

@end

NS_ASSUME_NONNULL_END
