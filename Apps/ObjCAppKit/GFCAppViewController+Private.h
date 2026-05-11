#import "GFCAppViewController.h"

@class GFCBundleSession;
@class GFCListTableController;

extern void *GFCControlInfoKey;

@interface GFCAppViewController ()

@property(nonatomic, strong) GFCBundleSession *session;
@property(nonatomic, strong) NSSplitView *rootSplitView;
@property(nonatomic, strong) NSSplitView *detailSplitView;
@property(nonatomic, strong) NSStackView *sidebarStack;
@property(nonatomic, strong) NSStackView *pageStack;
@property(nonatomic, strong) NSTextView *outputTextView;
@property(nonatomic, strong) NSMutableArray<NSButton *> *actionButtons;
@property(nonatomic, strong) NSMutableArray<GFCListTableController *> *tableControllers;
@property(nonatomic) BOOL didSetInitialSplitPositions;

- (void)renderSelectedPage;
- (void)appendOutput:(NSString *)text;
- (NSScrollView *)scrollView;
- (void)installDocumentView:(NSView *)documentView inScrollView:(NSScrollView *)scrollView;
- (NSStackView *)verticalStackWithSpacing:(CGFloat)spacing;
- (NSStackView *)horizontalStackWithSpacing:(CGFloat)spacing;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font textColor:(NSColor *)color;
- (NSTextField *)wrappingLabel:(NSString *)text font:(NSFont *)font textColor:(NSColor *)color;
- (NSDictionary *)dictionary:(id)value;
- (NSArray *)array:(id)value;
- (NSString *)string:(id)value;

@end

@interface GFCAppViewController (Controls)

- (NSView *)controlView:(NSDictionary *)control;

@end

@interface GFCAppViewController (Actions)

- (NSButton *)actionButton:(NSDictionary *)action;
- (NSView *)appearanceSection;
- (NSView *)setupSection;
- (void)refreshActionButtons;
- (NSDictionary<NSString *, NSString *> *)processEnvironment;
- (NSDictionary<NSString *, NSString *> *)processEnvironmentWithStep:(NSDictionary *)step;

@end
