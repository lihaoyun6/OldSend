#import <UIKit/UIKit.h>

@interface AppDelegate : NSObject <UIApplicationDelegate, UIAlertViewDelegate> {
    UIWindow *_window;
    UITabBarController *_tabs;
    UIAlertView *_wifiAlert;
}

@end
