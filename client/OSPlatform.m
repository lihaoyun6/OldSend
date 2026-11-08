#import "OSPlatform.h"
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>

BOOL OSIsPad(void) {
    /* userInterfaceIdiom is unavailable/unreliable when linked against the
       3.1.3 SDK; the hardware model string is what OldSeek uses in practice. */
    return [[[UIDevice currentDevice] model] rangeOfString:@"iPad"].location != NSNotFound;
}

UIFont *OSSmallFont(CGFloat size) {
    if (OSIsPad()) return [UIFont boldSystemFontOfSize:size];
    return [UIFont systemFontOfSize:size];
}

static NSString *OSEnsureDirectory(NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return path;
}

static NSString *OSDocumentsDirectory(void) {
    NSString *path;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    path = [paths count] > 0 ? [paths objectAtIndex:0]
                             : [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    return OSEnsureDirectory(path);
}

NSString *OSAppDataDirectory(void) {
    static NSString *directory = nil;
    if (directory == nil) {
        NSString *library;
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
                                                             NSUserDomainMask, YES);
        library = [paths count] > 0 ? [paths objectAtIndex:0]
                                    : [NSHomeDirectory() stringByAppendingPathComponent:@"Library"];
        directory = [[library stringByAppendingPathComponent:@"OldSend"] copy];
        OSEnsureDirectory(directory);
    }
    return directory;
}

NSString *OSReceivedDirectory(void) {
    return OSEnsureDirectory([OSDocumentsDirectory() stringByAppendingPathComponent:@"Received"]);
}

NSString *OSOutgoingDirectory(void) {
    return OSEnsureDirectory([OSDocumentsDirectory() stringByAppendingPathComponent:@"Outgoing"]);
}

NSString *OSLogFilePath(void) {
    return [OSAppDataDirectory() stringByAppendingPathComponent:@"oldsend.log"];
}

NSString *OSInitialBrowseDirectory(void) {
    return OSDocumentsDirectory();
}

static NSDictionary *OSInfoDictionaryForBundle(NSString *bundleID) {
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    NSFileManager *manager = [NSFileManager defaultManager];

    if (proxyClass == Nil) {
        dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
        dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
        proxyClass = NSClassFromString(@"LSApplicationProxy");
    }

    if (proxyClass != Nil) {
        id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:)
                                    withObject:bundleID];
        if (proxy != nil && [proxy respondsToSelector:@selector(infoDictionary)]) {
            id info = [proxy performSelector:@selector(infoDictionary)];
            if ([info isKindOfClass:[NSDictionary class]]) {
                OSLogDebug(@"proxy info for %@", bundleID);
                return info;
            }
        }
        if (proxy != nil && [proxy respondsToSelector:@selector(bundleURL)]) {
            NSURL *url = [proxy performSelector:@selector(bundleURL)];
            if (url != nil) {
                NSString *path = [[url path] stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:path];
                if (info != nil) {
                    OSLogDebug(@"proxy bundle %@", path);
                    return info;
                }
            }
        }
    }

    {
        NSArray *bases = [NSArray arrayWithObjects:
            @"/Applications", @"/var/mobile/Applications", nil];
        for (NSString *base in bases) {
            NSArray *entries = [manager contentsOfDirectoryAtPath:base error:NULL];
            for (NSString *entry in entries) {
                NSString *path = [base stringByAppendingPathComponent:entry];
                NSMutableArray *apps = [NSMutableArray array];

                if ([entry hasSuffix:@".app"]) {
                    [apps addObject:path];
                } else {
                    NSArray *inner = [manager contentsOfDirectoryAtPath:path error:NULL];
                    for (NSString *name in inner) {
                        if ([name hasSuffix:@".app"]) {
                            [apps addObject:[path stringByAppendingPathComponent:name]];
                        }
                    }
                }

                for (NSString *app in apps) {
                    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                        [app stringByAppendingPathComponent:@"Info.plist"]];
                    if ([[info objectForKey:@"CFBundleIdentifier"] isEqualToString:bundleID]) {
                        OSLogDebug(@"scanned bundle %@", app);
                        return info;
                    }
                }
            }
        }
    }

    return nil;
}

static NSString *OSSchemeForBundleIdentifier(NSString *bundleID) {
    NSDictionary *info = OSInfoDictionaryForBundle(bundleID);
    NSArray *types = [info objectForKey:@"CFBundleURLTypes"];

    for (NSDictionary *type in types) {
        NSArray *schemes = [type objectForKey:@"CFBundleURLSchemes"];
        if ([schemes count] > 0) return [schemes objectAtIndex:0];
    }
    return nil;
}

BOOL OSLaunchApplicationByBundleID(NSString *bundleID) {
    static void *handle = NULL;
    static int (*launch)(CFStringRef, Boolean) = NULL;

    if (bundleID == nil) return NO;

    if (handle == NULL) {
        handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
                        RTLD_LAZY);
        if (handle != NULL) {
            launch = (int (*)(CFStringRef, Boolean))dlsym(handle, "SBSLaunchApplicationWithIdentifier");
        }
    }
    if (launch != NULL) {
        int result = launch((CFStringRef)bundleID, false);
        OSLogDebug(@"SBS launch %@ -> %d", bundleID, result);
        if (result == 0) return YES;
    }

    {
        NSString *scheme = OSSchemeForBundleIdentifier(bundleID);
        if ([scheme length] > 0) {
            NSString *string = [scheme stringByAppendingString:@"://"];
            BOOL opened = [[UIApplication sharedApplication]
                           openURL:[NSURL URLWithString:string]];
            OSLogDebug(@"scheme open %@ -> %d", string, opened);
            if (opened) return YES;
        }
    }

    {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        OSLogDebug(@"LSApplicationWorkspace %@", workspaceClass);
        if (workspaceClass != Nil) {
            id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
            SEL selector = @selector(openApplicationWithBundleID:);
            if (workspace != nil && [workspace respondsToSelector:selector]) {
                IMP imp = [workspace methodForSelector:selector];
                ((void (*)(id, SEL, id))imp)(workspace, selector, bundleID);
                OSLogDebug(@"LSApplicationWorkspace open %@", bundleID);
                return YES;
            }
        }
    }

    return NO;
}

BOOL OSApplicationExists(NSString *bundleID) {
    return OSInfoDictionaryForBundle(bundleID) != nil;
}

void OSLogDebug(NSString *format, ...) {
#ifdef DEBUG
    va_list args;
    NSString *line;
    FILE *file;

    va_start(args, format);
    line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"OldSend: %@", line);

    file = fopen([OSLogFilePath() fileSystemRepresentation], "a");
    if (file != NULL) {
        fprintf(file, "%s\n", [line UTF8String]);
        fflush(file);
        fclose(file);
    }
    [line release];
#endif
}
