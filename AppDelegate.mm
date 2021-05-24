#import "AppDelegate.h"

#ifdef __aarch64__
#define ARCH_KEY_NAME @"aarch64"
#else
#define ARCH_KEY_NAME @"x86_64"
#endif

const NSTimeInterval kDefaultTimeoutSecs = 60 * 60 * 12;  // 12 hours

void showErrorModal(NSString* errorDecription) {
  NSDictionary* info = [[NSBundle mainBundle] infoDictionary];
  NSDictionary* downloadURLs = [info objectForKey:@"TargetDownloadURLs"];
  NSURL* downloadURL = [NSURL URLWithString:[downloadURLs valueForKey:ARCH_KEY_NAME]];
  NSString* targetAppName = [info valueForKey:@"TargetAppName"];

  NSString* errorText = @"";
  if (errorDecription) {
    errorText = [NSString stringWithFormat:@"\n\nYou may also contact %@ support with this error "
                                           @"information:\n\n%@",
                                           targetAppName, errorDecription];
  }

  NSAlert* alert = [[NSAlert alloc] init];
  [alert addButtonWithTitle:@"Download manually"];
  [alert addButtonWithTitle:@"Cancel"];
  [alert setMessageText:[NSString
                            stringWithFormat:@"%@ Automatic Installation Failed", targetAppName]];
  [alert setInformativeText:[NSString stringWithFormat:@"Download %@ manually to continue.%@",
                                                       targetAppName, errorText]];
  [alert setAlertStyle:NSAlertStyleCritical];

  [NSApp activateIgnoringOtherApps:YES];
  if ([alert runModal] == NSAlertFirstButtonReturn) {
    [[NSWorkspace sharedWorkspace] openURL:downloadURL];
  }

  [NSApp terminate:nullptr];
}

void showErrorModal(NSError* error) {
  auto* errorDescription =
      [NSString stringWithFormat:@"%@ (code %ld)", error.localizedDescription, error.code];
  showErrorModal(errorDescription);
}

@interface AppDelegate ()
@property(weak) IBOutlet NSWindow* window;
@property(weak) IBOutlet NSTextField* label;
@property(weak) IBOutlet NSProgressIndicator* progressIndicator;

@property NSURLSessionDownloadTask* task;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  // First check if trying to run `sh -c ...` works. We'll be using it at
  // the end to relaunch the app.
  NSTask* checkTask = [[NSTask alloc] init];
  [checkTask setLaunchPath:@"/bin/sh"];
  [checkTask setArguments:@[ @"-c", @"sleep 0 && which open && which unzip" ]];
  [checkTask launch];
  [checkTask waitUntilExit];
  if (checkTask.terminationStatus != 0) {
    showErrorModal(
        [NSString stringWithFormat:@"Initial check failed: %i", checkTask.terminationStatus]);
    return;
  }

  NSDictionary* info = NSBundle.mainBundle.infoDictionary;
  NSDictionary* downloadURLs = [info objectForKey:@"TargetDownloadURLs"];
  NSURL* downloadURL = [NSURL URLWithString:[downloadURLs valueForKey:ARCH_KEY_NAME]];
  NSString* targetAppName = [info valueForKey:@"TargetAppName"];

  self.window.title = [NSString stringWithFormat:@"%@ Installer", targetAppName];
  self.label.stringValue = [NSString stringWithFormat:@"Downloading %@...", targetAppName];

  // Fetch the platform specific build archive.
  NSURLRequest* request = [NSURLRequest requestWithURL:downloadURL
                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                       timeoutInterval:kDefaultTimeoutSecs];
  self.task = [NSURLSession.sharedSession
      downloadTaskWithRequest:request
            completionHandler:^(NSURL* downloadLocation, NSURLResponse* response, NSError* error) {
              if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                  showErrorModal(error);
                });

                return;
              }

              if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                const auto statusCode = ((NSHTTPURLResponse*)response).statusCode;
                if (statusCode < 200 || statusCode >= 300) {
                  dispatch_async(dispatch_get_main_queue(), ^{
                    showErrorModal(
                        [NSString stringWithFormat:@"Failed to download, HTTP: %lu", statusCode]);
                  });

                  return;
                }
              }

              dispatch_async(dispatch_get_main_queue(), ^{
                self.label.stringValue =
                    [NSString stringWithFormat:@"Installing %@...", targetAppName];
                self.progressIndicator.indeterminate = true;
              });

              // Big Sur and later have APIs to extract archives, but we need
              // to support older versions. Lets use plain old unzip to
              // extract the downloaded archive.
              //
              // TODO(poiru): Support XZ archives.
              // TODO(poiru): Handle error.
              NSTask* task = [[NSTask alloc] init];
              [task setLaunchPath:@"/usr/bin/unzip"];
              [task setArguments:@[ @"-qq", @"-o", @"-d", @"/Applications", location.path ]];
              [task launch];
              [task waitUntilExit];
              [[NSFileManager defaultManager] removeItemAtPath:location.path error:nil];

              dispatch_async(dispatch_get_main_queue(), ^{
                [self launchInstalledApp];
              });
            }];
  [self.task resume];

  [self.task.progress addObserver:self
                       forKeyPath:@"fractionCompleted"
                          options:NSKeyValueObservingOptionNew
                          context:nil];
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id>*)change
                       context:(void*)context {
  if ([keyPath isEqual:@"fractionCompleted"]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      const auto value = [[change valueForKey:NSKeyValueChangeNewKey] doubleValue];
      self.progressIndicator.doubleValue = value;
    });
  }
}

- (void)applicationWillTerminate:(NSNotification*)notification {
  [self.task cancel];
}

- (void)applicationDidBecomeActive:(NSNotification*)notification {
  if (self.task.state == NSURLSessionTaskStateCompleted) {
    [self launchInstalledApp];
  }
}

- (IBAction)cancelClicked:(id)sender {
  [self.task cancel];
  [NSApp terminate:nullptr];
}

- (void)launchInstalledApp {
  // Spawn a sh process to relaunch the installed app after we exit. Otherwise
  // the new app might not launch if this stub app is already running at the
  // path.
  NSTask* launchTask = [[NSTask alloc] init];
  [launchTask setLaunchPath:@"/bin/sh"];
  [launchTask setArguments:@[
    @"-c", [NSString stringWithFormat:@"sleep 1; /usr/bin/open %s \"/Applications/%@.app\"",
                                      self.window.isMainWindow ? "" : "-g", targetAppName]
  ]];
  [launchTask launch];
  [NSApp terminate:nullptr];
}

@end
