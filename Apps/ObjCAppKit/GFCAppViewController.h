#import <Cocoa/Cocoa.h>

@class GFCBundleSession;

NS_ASSUME_NONNULL_BEGIN

@interface GFCAppViewController : NSViewController <NSTextFieldDelegate>

- (instancetype)initWithSession:(GFCBundleSession *)session;

@end

NS_ASSUME_NONNULL_END
