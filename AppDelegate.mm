#import "AppDelegate.h"
#import "STPrivilegedTask.h"

#include <sys/sysctl.h>

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
    NSString* contactSupportMessage =
        [NSString stringWithFormat:(NSLocalizedString(@"errorDialog.contactSupportMessage", nil)),
                                   targetAppName];
    errorText = [NSString stringWithFormat:@"\n\n%@\n\n%@", contactSupportMessage, errorDecription];
  }

  NSAlert* alert = [[NSAlert alloc] init];
  [alert addButtonWithTitle:(NSLocalizedString(@"errorDialog.downloadManuallyButton", nil))];
  [alert addButtonWithTitle:(NSLocalizedString(@"dialog.cancelButton", nil))];
  [alert setMessageText:[NSString stringWithFormat:(NSLocalizedString(@"errorDialog.title", nil)),
                                                   targetAppName]];
  NSString* downloadManuallyMessage =
      [NSString stringWithFormat:(NSLocalizedString(@"errorDialog.downloadManuallyMessage", nil)),
                                 targetAppName];
  [alert
      setInformativeText:[NSString stringWithFormat:@"%@%@", downloadManuallyMessage, errorText]];
  [alert setAlertStyle:NSAlertStyleCritical];

  [NSApp activateIgnoringOtherApps:YES];
  if ([alert runModal] == NSAlertFirstButtonReturn) {
    [[NSWorkspace sharedWorkspace] openURL:downloadURL];
  }

  [NSApp terminate:nullptr];
}

void runCommand(NSString* path, NSArray* arg) {
  NSTask* task = [[NSTask alloc] init];
  [task setLaunchPath:path];
  [task setArguments:arg];
  [task launch];
  [task waitUntilExit];
}

void showErrorModal(NSError* error) {
  auto* errorDescription =
      [NSString stringWithFormat:(NSLocalizedString(@"error.errorWithCode", nil)),
                                 error.localizedDescription, error.code];
  showErrorModal(errorDescription);
}

bool isBundleWritable() {
  auto* testDir = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"test"];
  auto* fileManager = NSFileManager.defaultManager;
  bool result = [fileManager createDirectoryAtPath:testDir
                       withIntermediateDirectories:true
                                        attributes:nil
                                             error:nil];
  if (result) {
    [fileManager removeItemAtPath:testDir error:nil];
    return true;
  } else {
    return false;
  }
}

@interface AppDelegate ()
@property(weak) IBOutlet NSWindow* window;
@property(weak) IBOutlet NSTextField* label;
@property(weak) IBOutlet NSProgressIndicator* progressIndicator;
@property(weak) IBOutlet NSButton* cancelButton;
@property(weak) IBOutlet NSMenuItem* quitMenuItem;

@property NSURLSessionDownloadTask* task;
@end

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification*)notification {
  // Localize menu items
  NSString* installerName = [NSBundle.mainBundle.infoDictionary valueForKey:@"CFBundleName"];
  self.quitMenuItem.title =
      [NSString stringWithFormat:NSLocalizedString(@"menu.quitItem", nil), installerName];

  // On macOS 10.12+, app bundles downloaded from the internet are launched
  // from a randomized path until the user moves it to another folder with
  // Finder. See: https://github.com/potionfactory/LetsMove/issues/56
  if ([NSBundle.mainBundle.bundlePath hasPrefix:@"/private/var/folders/"]) {
    NSDictionary* info = NSBundle.mainBundle.infoDictionary;
    NSString* targetAppName = [info valueForKey:@"TargetAppName"];

    NSAlert* alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:NSLocalizedString(@"dialog.okButton", nil)];
    [alert setMessageText:NSLocalizedString(@"moveToApplicationsDialog.title", nil)];
    [alert setInformativeText:[NSString
                                  stringWithFormat:(NSLocalizedString(
                                                       @"moveToApplicationsDialog.message", nil)),
                                                   targetAppName]];
    [alert setAlertStyle:NSAlertStyleCritical];
    [alert runModal];
    [NSApp terminate:nullptr];
  }

  // First check if trying to run `sh -c ...` works. We'll be using it at
  // the end to relaunch the app.
  NSTask* checkTask = [[NSTask alloc] init];
  [checkTask setLaunchPath:@"/bin/sh"];
  [checkTask setArguments:@[ @"-c", @"sleep 0 && which open && which unzip" ]];
  [checkTask launch];
  [checkTask waitUntilExit];
  if (checkTask.terminationStatus != 0) {
    showErrorModal([NSString stringWithFormat:(NSLocalizedString(@"error.initialCheckFailed", nil)),
                                              checkTask.terminationStatus]);
    return;
  }
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  NSDictionary* info = NSBundle.mainBundle.infoDictionary;
  NSDictionary* downloadURLs = [info objectForKey:@"TargetDownloadURLs"];
  NSURL* downloadURL = [NSURL URLWithString:[downloadURLs valueForKey:ARCH_KEY_NAME]];
  NSString* targetAppName = [info valueForKey:@"TargetAppName"];

  if (!isBundleWritable()) {
    // If permission check fails, it's likely to be a standard user, let's rerun the program
    // as root

    if (geteuid() != 0) {
      STPrivilegedTask* task = [STPrivilegedTask new];
      [task setLaunchPath:[NSBundle.mainBundle executablePath]];
      [task launch];
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{
        showErrorModal(NSLocalizedString(@"error.wrongPermissions", nil));
      });
    }
    return;
  }

  self.window.title =
      [NSString stringWithFormat:(NSLocalizedString(@"installerDialog.title", nil)), targetAppName];
  self.label.stringValue =
      [NSString stringWithFormat:(NSLocalizedString(@"installerDialog.downloadingMessage", nil)),
                                 targetAppName];
  self.cancelButton.title = NSLocalizedString(@"dialog.cancelButton", nil);

  [self.window setIsVisible:TRUE];
  [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];

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

              if ([response isKindOfClass:NSHTTPURLResponse.class]) {
                const auto statusCode = ((NSHTTPURLResponse*)response).statusCode;
                if (statusCode < 200 || statusCode >= 300) {
                  dispatch_async(dispatch_get_main_queue(), ^{
                    showErrorModal([NSString
                        stringWithFormat:(NSLocalizedString(@"error.downloadFailed", nil)),
                                         statusCode]);
                  });

                  return;
                }
              }

              dispatch_async(dispatch_get_main_queue(), ^{
                self.label.stringValue = [NSString
                    stringWithFormat:(NSLocalizedString(@"installerDialog.installingMessage", nil)),
                                     targetAppName];
              });

              // Big Sur and later have APIs to extract archives, but we need
              // to support older versions. Lets use plain old unzip to
              // extract the downloaded archive.
              //
              // TODO(poiru): Support XZ archives.
              auto* fileManager = NSFileManager.defaultManager;
              auto* tempDir =
                  [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"download"];

              NSTask* task = [[NSTask alloc] init];
              [task setLaunchPath:@"/usr/bin/unzip"];
              [task setArguments:@[ @"-qq", @"-o", @"-d", tempDir, downloadLocation.path ]];
              [task launch];
              [task waitUntilExit];
              [fileManager removeItemAtPath:downloadLocation.path error:nil];

              if (task.terminationStatus != 0) {
                [fileManager removeItemAtPath:tempDir error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                  showErrorModal(
                      [NSString stringWithFormat:(NSLocalizedString(@"error.extractFailed", nil)),
                                                 task.terminationStatus]);
                });
                return;
              }

              auto* sourcePath = [tempDir
                  stringByAppendingPathComponent:[NSString
                                                     stringWithFormat:@"%@.app", targetAppName]];
              auto* targetPath = NSBundle.mainBundle.bundlePath;
              // Rename the final bundle in the temp directory to the target directory.
              // Lets first try using the rename() system call because it can do that
              // atomically even if the the target already exists.
              if (rename(sourcePath.fileSystemRepresentation,
                         targetPath.fileSystemRepresentation) != 0) {
                // If rename() failed, try to do this by moving the contents instead
                // Advantage of this approach is that we don't need any special permissions if the
                // user is the owner of the folder (User initiated drag and drop) Disadvantage of
                // this approach is that the metadata update isn't reliable, if the icon of the app
                // and the replaced app are different, user may need a restart before the icon
                // updates in the dock.

                NSDirectoryEnumerator* enumerator = [fileManager enumeratorAtPath:sourcePath];
                NSString* file;

                while (file = [enumerator nextObject]) {
                  NSError* error = nil;
                  BOOL result = rename(
                      [sourcePath stringByAppendingPathComponent:file].fileSystemRepresentation,
                      [targetPath stringByAppendingPathComponent:file].fileSystemRepresentation);

                  if (!result && error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                      showErrorModal(error);
                    });
                    return;
                  }
                }

                // Trigger icon updation
                runCommand(@"/usr/bin/touch", @[ NSBundle.mainBundle.bundlePath ]);
                runCommand(@"/usr/bin/touch",
                           @[ [NSBundle.mainBundle.bundlePath
                               stringByAppendingPathComponent:@"Contents/Info.plist"] ]);
              }

              [fileManager removeItemAtPath:tempDir error:nil];

              dispatch_async(dispatch_get_main_queue(), ^{
                [self launchInstalledApp];
              });
            }];
  [self.task resume];

  if (@available(macOS 10.13, *)) {
    [self.task.progress addObserver:self
                         forKeyPath:@"fractionCompleted"
                            options:NSKeyValueObservingOptionNew
                            context:nil];
  } else {
    self.progressIndicator.indeterminate = TRUE;
  }
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id>*)change
                       context:(void*)context {
  if ([keyPath isEqual:@"fractionCompleted"]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      const auto value = [[change valueForKey:NSKeyValueChangeNewKey] doubleValue];
      self.progressIndicator.doubleValue = fmax(self.progressIndicator.doubleValue, value * 0.95);
    });
  }
}

- (void)applicationWillTerminate:(NSNotification*)notification {
  [self.task cancel];
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
    @"-c",
    [NSString stringWithFormat:@"sleep 1; /usr/bin/open %s \"%@\"",
                               self.window.isMainWindow ? "" : "-g", NSBundle.mainBundle.bundlePath]
  ]];
  [launchTask launch];
  [NSApp terminate:nullptr];
}

@end
