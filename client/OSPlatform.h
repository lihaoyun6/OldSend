#import <UIKit/UIKit.h>

/* YES on iPad, including iPad 1 running iPhone OS 3.2 / 4.x. */
BOOL OSIsPad(void);

/* Small hint text: bold on iPad, regular on iPhone/iPod. */
UIFont *OSSmallFont(CGFloat size);

/* System app (/Applications) keeps the old shared paths; sandboxed IPA builds
   use their own writable container. */
NSString *OSAppDataDirectory(void);
NSString *OSReceivedDirectory(void);
NSString *OSOutgoingDirectory(void);
NSString *OSLogFilePath(void);
NSString *OSInitialBrowseDirectory(void);

/* Launch another app by bundle id (jailbroken devices). */
BOOL OSLaunchApplicationByBundleID(NSString *bundleID);
void OSLogDebug(NSString *format, ...);
