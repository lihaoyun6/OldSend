#import <UIKit/UIKit.h>

@class SendViewController;

@interface AppDelegate : NSObject <UIApplicationDelegate, UIAlertViewDelegate> {
    UIWindow *_window;
    UITabBarController *_tabs;
    UIAlertView *_wifiAlert;
    SendViewController *_sendController;
    SendViewController *_shareController;
    BOOL _dismissShareOnBackground;
    NSString *_returnBundleIdentifier;
}

@end
