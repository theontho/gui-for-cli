#import <Cocoa/Cocoa.h>

CFAbsoluteTime GFCAppStartTime;

int main(int argc, const char *argv[]) {
  GFCAppStartTime = CFAbsoluteTimeGetCurrent();
  printf("metric processStarted_ms=0.0\n");
  fflush(stdout);
  return NSApplicationMain(argc, argv);
}
