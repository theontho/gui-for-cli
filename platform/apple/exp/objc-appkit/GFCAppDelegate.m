#import "GFCAppDelegate.h"
#import "GFCAppViewController.h"
#import "GFCBundleSession.h"

@interface GFCAppDelegate ()

@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSDate *launchDate;

@end

@implementation GFCAppDelegate

- (instancetype)init {
  self = [super init];
  if (self) {
    _launchDate = [NSDate date];
  }
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  [self installMainMenu];
  NSError *error = nil;
  GFCBundleSession *session = [GFCBundleSession loadDefaultSessionWithError:&error];
  NSViewController *contentController = nil;
  if (session != nil) {
    contentController = [[GFCAppViewController alloc] initWithSession:session];
  } else {
    NSTextField *label = [NSTextField wrappingLabelWithString:error.localizedDescription ?: @"Could not load the bundle."];
    label.frame = NSMakeRect(24, 24, 720, 200);
    NSViewController *errorController = [[NSViewController alloc] init];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 480)];
    [view addSubview:label];
    errorController.view = view;
    contentController = errorController;
  }

  NSString *title = session.manifest[@"displayName"] ?: @"GUI for CLI";
  NSSize contentSize = NSMakeSize(1180, 820);
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, contentSize.width, contentSize.height)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  self.window.minSize = NSMakeSize(960, 680);
  self.window.title = title;
  self.window.contentViewController = contentController;
  [self.window setContentSize:contentSize];
  [self.window center];
  if ([NSProcessInfo.processInfo.environment[@"GFC_BENCHMARK_PRESERVE_FOCUS"] isEqualToString:@"1"]) {
    [self.window orderFront:nil];
  } else {
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
  }
  [self printBenchmarkMarkerIfNeeded];
}

- (void)installMainMenu {
  NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
  NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:appMenuItem];

  NSString *appName = NSProcessInfo.processInfo.processName ?: @"GUI for CLI ObjC AppKit Test";
  NSMenu *appMenu = [[NSMenu alloc] initWithTitle:appName];
  NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Quit %@", appName]
                                                action:@selector(terminate:)
                                         keyEquivalent:@"q"];
  quit.target = NSApp;
  [appMenu addItem:quit];
  appMenuItem.submenu = appMenu;
  NSApp.mainMenu = mainMenu;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return YES;
}

- (void)printBenchmarkMarkerIfNeeded {
  if (![self benchmarkEnabled]) {
    return;
  }
  NSTimeInterval elapsedMilliseconds = [[NSDate date] timeIntervalSinceDate:self.launchDate] * 1000.0;
  printf("gfc-objc-appkit benchmark window_appeared_ms=%.1f\n", elapsedMilliseconds);
  fflush(stdout);
}

- (BOOL)benchmarkEnabled {
  if ([NSProcessInfo.processInfo.environment[@"GFC_BENCHMARK_STARTUP"] isEqualToString:@"1"]) {
    return YES;
  }
  return [NSProcessInfo.processInfo.arguments containsObject:@"--benchmark"];
}

@end
