#import <Cocoa/Cocoa.h>
#import "GFCAppDelegate.h"

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSApplication *application = NSApplication.sharedApplication;
    GFCAppDelegate *delegate = [[GFCAppDelegate alloc] init];
    application.delegate = delegate;
    [application run];
  }
  return 0;
}
