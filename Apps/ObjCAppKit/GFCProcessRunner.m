#import "GFCProcessRunner.h"

@implementation GFCProcessRunner

+ (void)runExecutable:(NSString *)executable
            arguments:(NSArray<NSString *> *)arguments
     workingDirectory:(NSString *)workingDirectory
          environment:(NSDictionary<NSString *, NSString *> *)environment
           completion:(GFCProcessCompletion)completion {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments;
    task.currentDirectoryURL = [NSURL fileURLWithPath:workingDirectory isDirectory:YES];

    NSMutableDictionary *mergedEnvironment = [NSProcessInfo.processInfo.environment mutableCopy];
    [mergedEnvironment addEntriesFromDictionary:environment];
    task.environment = mergedEnvironment;

    NSPipe *outputPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = outputPipe;

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(@"", -1, launchError);
      });
      return;
    }

    [task waitUntilExit];
    NSData *data = [outputPipe.fileHandleForReading readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    int exitCode = task.terminationStatus;
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(output, exitCode, nil);
    });
  });
}

@end
