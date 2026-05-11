#import "GFCAppDelegate.h"
#import "GFCAppViewController.h"
#import "GFCBundleSession.h"

@interface GFCAppDelegate ()

@property(nonatomic, strong) NSWindow *window;

@end

@implementation GFCAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
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
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1020, 740)
                                           styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                             backing:NSBackingStoreBuffered
                                               defer:NO];
  self.window.title = title;
  self.window.contentViewController = contentController;
  [self.window center];
  [self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return YES;
}

@end
