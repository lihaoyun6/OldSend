#import "OSPlatform.h"
#import <Foundation/Foundation.h>

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
