#import "AppDelegate.h"
#include <string.h>
#include <netinet/in.h>
#import "ReceiveViewController.h"
#import "SendViewController.h"
#import "FilesViewController.h"
#import "SettingsViewController.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "OSServer.h"
#import "OSPlatform.h"
#import "OSNavigationController.h"

static NSString *OSQueryValue(NSString *query, NSString *key) {
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        NSRange separator = [pair rangeOfString:@"="];
        if (separator.location == NSNotFound) continue;
        if (![[pair substringToIndex:separator.location] isEqualToString:key]) continue;
        return [[pair substringFromIndex:separator.location + 1]
                stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }
    return nil;
}

static NSString *OSDecodeMarkerText(NSString *text) {
    NSString *decoded = [text stringByReplacingOccurrencesOfString:@"%0A" withString:@"\n"];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"%0D" withString:@"\r"];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"%25" withString:@"%"];
    return decoded;
}

static NSString *OSShareTemporaryDirectory(void) {
    NSString *directory = [NSTemporaryDirectory()
                           stringByAppendingPathComponent:@"OldSendShare"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return directory;
}

@interface UIWindow (OSRootViewController)
- (void)setRootViewController:(UIViewController *)controller;
@end

@interface OSTabBarController : UITabBarController
@end

@implementation OSTabBarController

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if (OSIsPad()) return YES;
    return orientation == UIInterfaceOrientationPortrait;
}

- (UIViewController *)visibleContentController {
    UIViewController *controller = self.selectedViewController;
    if ([controller isKindOfClass:[UINavigationController class]]) {
        controller = [(UINavigationController *)controller topViewController];
    }
    return controller;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation
                                         duration:(NSTimeInterval)duration {
    [super willAnimateRotationToInterfaceOrientation:orientation duration:duration];
    [[self visibleContentController] willAnimateRotationToInterfaceOrientation:orientation
                                                                      duration:duration];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    [super didRotateFromInterfaceOrientation:orientation];
    [[self visibleContentController] didRotateFromInterfaceOrientation:orientation];
}

@end

@implementation AppDelegate

static BOOL OSIsWiFiReachable(void) {
    struct sockaddr_in zeroAddress;
    SCNetworkReachabilityRef reachability;
    SCNetworkReachabilityFlags flags = 0;
    BOOL reachable;
    BOOL needsConnection;

    memset(&zeroAddress, 0, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;

    reachability = SCNetworkReachabilityCreateWithAddress(
        NULL, (const struct sockaddr *)&zeroAddress);
    if (reachability == NULL) return YES;

    if (!SCNetworkReachabilityGetFlags(reachability, &flags)) {
        CFRelease(reachability);
        return YES;
    }
    CFRelease(reachability);

    reachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    needsConnection = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
#if TARGET_OS_IPHONE
    if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) return NO;
#endif
    return reachable && !needsConnection;
}

- (void)showWiFiAlertIfNeeded {
    if (OSIsWiFiReachable()) return;
    if (_wifiAlert != nil) return;

    _wifiAlert = [[UIAlertView alloc]
        initWithTitle:NSLocalizedString(@"wifi.missing_title", nil)
              message:NSLocalizedString(@"wifi.missing_message", nil)
             delegate:self
    cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
    otherButtonTitles:nil];
    [_wifiAlert show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (alertView == _wifiAlert) {
        [_wifiAlert release];
        _wifiAlert = nil;
        [_window makeKeyAndVisible];
    }
}

- (UINavigationController *)navigationControllerWithController:(UIViewController *)controller
                                                          title:(NSString *)title
                                                          image:(NSString *)image
                                                     systemItem:(NSInteger)systemItem
                                                            tag:(NSInteger)tag {
    UINavigationController *navigation = [[OSNavigationController alloc]
                                          initWithRootViewController:controller];
    UITabBarItem *item;

    if (image == nil) {
        item = [[UITabBarItem alloc] initWithTabBarSystemItem:(UITabBarSystemItem)systemItem
                                                          tag:tag];
        item.title = title;
    } else {
        item = [[UITabBarItem alloc] initWithTitle:title
                                            image:[UIImage imageNamed:image]
                                              tag:tag];
    }
    navigation.tabBarItem = item;
    [item release];
    return [navigation autorelease];
}

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    ReceiveViewController *receive = [[ReceiveViewController alloc] init];
    SendViewController *send = [[SendViewController alloc] init];
    FilesViewController *files = [[FilesViewController alloc] init];
    SettingsViewController *settings = [[SettingsViewController alloc] init];

    UINavigationController *receiveNavigation =
        [self navigationControllerWithController:receive
                                           title:NSLocalizedString(@"tab.receive", nil)
                                           image:@"TabReceive.png"
                                      systemItem:-1
                                             tag:0];
    UINavigationController *sendNavigation =
        [self navigationControllerWithController:send
                                           title:NSLocalizedString(@"tab.send", nil)
                                           image:@"TabSend.png"
                                      systemItem:-1
                                             tag:1];
    UINavigationController *filesNavigation =
        [self navigationControllerWithController:files
                                           title:NSLocalizedString(@"tab.files", nil)
                                           image:@"TabHistory.png"
                                      systemItem:-1
                                             tag:2];
    UINavigationController *settingsNavigation =
        [self navigationControllerWithController:settings
                                           title:NSLocalizedString(@"tab.settings", nil)
                                           image:@"TabSettings.png"
                                      systemItem:-1
                                             tag:3];

    _sendController = send;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(shareSendDidDismiss:)
                                                 name:@"OSShareSendDidDismiss"
                                               object:nil];

    [receive release];
    [send release];
    [files release];
    [settings release];

    _tabs = [[OSTabBarController alloc] init];
    _tabs.viewControllers = [NSArray arrayWithObjects:
                             receiveNavigation, sendNavigation, filesNavigation,
                             settingsNavigation, nil];

    if ([_window respondsToSelector:@selector(setRootViewController:)]) {
        [_window setRootViewController:_tabs];
    } else {
        [_window addSubview:_tabs.view];
    }
    [_window makeKeyAndVisible];

    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    [[OSServer shared] start];

    [self performSelector:@selector(showWiFiAlertIfNeeded)
               withObject:nil
               afterDelay:1.5];
    [self performSelector:@selector(startShareTemporaryCleanup)
               withObject:nil
               afterDelay:2.0];
}

static NSString *OSUniqueIncomingPath(NSString *directory, NSString *name) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *path = [directory stringByAppendingPathComponent:name];
    NSString *base;
    NSString *extension;
    int index;

    if (![manager fileExistsAtPath:path]) return path;

    base = [name stringByDeletingPathExtension];
    extension = [name pathExtension];
    index = 2;
    while (1) {
        NSString *candidateName = [extension length] > 0
            ? [NSString stringWithFormat:@"%@-%d.%@", base, index, extension]
            : [NSString stringWithFormat:@"%@-%d", base, index];
        NSString *candidate = [directory stringByAppendingPathComponent:candidateName];
        if (![manager fileExistsAtPath:candidate]) return candidate;
        index++;
    }
}

- (BOOL)openIncomingDocument:(NSURL *)url source:(NSString *)source {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *directory;
    NSString *destination;
    NSString *base;

    if ([[url scheme] isEqualToString:@"oldsend"]) {
        NSString *text = OSQueryValue([url query], @"text");
        if ([text length] == 0) return NO;

        [_returnBundleIdentifier release];
        _returnBundleIdentifier = [(source != nil ? source : @"com.apple.mobilesafari") copy];

        {
            NSArray *items = [NSArray arrayWithObject:
                [NSDictionary dictionaryWithObjectsAndKeys:
                    @"text", @"kind", text, @"text", nil]];
            [self performSelector:@selector(presentShareSendWithItems:)
                       withObject:items
                       afterDelay:0.3];
        }
        return YES;
    }

    if (![url isFileURL]) return NO;

    [_returnBundleIdentifier release];
    _returnBundleIdentifier = [source copy];
    OSLogDebug(@"document open source=%@ file=%@", source, [url path]);

    directory = OSShareTemporaryDirectory();
    base = [NSString stringWithFormat:@"share-%u-%@",
            (unsigned)[[NSDate date] timeIntervalSince1970],
            [[url path] lastPathComponent]];
    destination = OSUniqueIncomingPath(directory, base);

    if (![manager moveItemAtPath:[url path] toPath:destination error:NULL]) {
        if (![manager copyItemAtPath:[url path] toPath:destination error:NULL]) return NO;
        [manager removeItemAtPath:[url path] error:NULL];
    }

    [self performSelector:@selector(presentShareSendWithPaths:)
               withObject:[NSArray arrayWithObject:destination]
               afterDelay:0.3];
    return YES;
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    return [self openIncomingDocument:url source:nil];
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    return [self openIncomingDocument:url source:sourceApplication];
}

- (void)processPendingImports {
    NSString *directory = OSShareTemporaryDirectory();
    NSString *marker = [directory stringByAppendingPathComponent:@".oldsend-import"];
    NSString *content = [NSString stringWithContentsOfFile:marker
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
    NSMutableArray *items = [NSMutableArray array];

    if ([content length] == 0) return;
    [[NSFileManager defaultManager] removeItemAtPath:marker error:NULL];

    {
        NSString *sourcePath = [directory stringByAppendingPathComponent:@".oldsend-source"];
        NSString *source = [NSString stringWithContentsOfFile:sourcePath
                                                     encoding:NSUTF8StringEncoding
                                                        error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:sourcePath error:NULL];
        source = [source stringByTrimmingCharactersInSet:
                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([source length] == 0) source = @"com.apple.mobileslideshow";
        [_returnBundleIdentifier release];
        _returnBundleIdentifier = [source copy];
    }

    for (NSString *line in [content componentsSeparatedByCharactersInSet:
                            [NSCharacterSet newlineCharacterSet]]) {
        NSString *name = [line stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *path;

        if ([name length] == 0) continue;
        if ([name hasPrefix:@"text:"]) {
            NSString *text = OSDecodeMarkerText([name substringFromIndex:5]);
            if ([text length] > 0) {
                [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    @"text", @"kind", text, @"text", nil]];
            }
            continue;
        }
        path = [directory stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                @"file", @"kind", path, @"path", nil]];
        }
    }

    if ([items count] == 0) return;
    [self performSelector:@selector(presentShareSendWithItems:)
               withObject:items
               afterDelay:0.3];
}

- (void)presentShareSendWithItems:(NSArray *)items {
    if (_shareController != nil && _shareController.view.window == nil) {
        _shareController = nil;
    }

    if (_shareController == nil) {
        SendViewController *controller = [[SendViewController alloc] init];
        UINavigationController *navigation;

        _dismissShareOnBackground = NO;
        [controller enableShareMode];
        [controller setReturnBundleIdentifier:_returnBundleIdentifier];
        navigation = [[OSNavigationController alloc] initWithRootViewController:controller];
        _shareController = controller;

        [_tabs presentModalViewController:navigation animated:YES];

        [navigation release];
        [controller release];
    }

    for (NSDictionary *item in items) {
        if ([[item objectForKey:@"kind"] isEqualToString:@"text"]) {
            [_shareController addPendingText:[item objectForKey:@"text"]];
        } else {
            [_shareController addPendingFilePath:[item objectForKey:@"path"]];
        }
    }
}

- (void)presentShareSendWithPaths:(NSArray *)paths {
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *path in paths) {
        [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            @"file", @"kind", path, @"path", nil]];
    }
    [self presentShareSendWithItems:items];
}

- (void)presentShareSendWithPath:(NSString *)path {
    [self presentShareSendWithPaths:[NSArray arrayWithObject:path]];
}

- (void)cleanupShareTemporaryFiles {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *directory = OSShareTemporaryDirectory();
    NSString *marker = [directory stringByAppendingPathComponent:@".oldsend-import"];
    NSFileManager *manager = [NSFileManager defaultManager];

    if (![manager fileExistsAtPath:marker]) {
        NSArray *files = [manager contentsOfDirectoryAtPath:directory error:NULL];
        for (NSString *name in files) {
            if ([name hasPrefix:@"share-"]) {
                [manager removeItemAtPath:[directory stringByAppendingPathComponent:name]
                                    error:NULL];
            }
        }
    }
    [pool release];
}

- (void)startShareTemporaryCleanup {
    if (_shareController != nil) return;
    [self performSelectorInBackground:@selector(cleanupShareTemporaryFiles)
                           withObject:nil];
}

- (void)shareSendDidDismiss:(NSNotification *)notification {
    _dismissShareOnBackground = YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    if (_dismissShareOnBackground) {
        [_tabs dismissModalViewControllerAnimated:NO];
        _shareController = nil;
        _dismissShareOnBackground = NO;
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [self processPendingImports];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    [[OSServer shared] stop];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_returnBundleIdentifier release];
    [_wifiAlert release];
    [_tabs release];
    [_window release];
    [super dealloc];
}

@end
