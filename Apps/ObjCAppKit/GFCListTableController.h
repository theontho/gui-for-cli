#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface GFCListTableController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithControl:(NSDictionary *)control
                           rows:(NSArray<NSDictionary *> *)rows
                         target:(id)target
                 actionSelector:(SEL)actionSelector
                  actionButtons:(NSMutableArray<NSButton *> *)actionButtons;
- (NSScrollView *)makeTableScrollView;

@end

NS_ASSUME_NONNULL_END
