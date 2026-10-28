#import <UIKit/UIKit.h>

@interface ReceiveViewController : UIViewController {
    UIImageView *_wifiView;
    UIImageView *_wifiBlueView;
    UILabel *_nameLabel;
    UILabel *_statusLabel;
    UIProgressView *_progressView;
    UILabel *_progressLabel;
    UILabel *_footerLabel;
    BOOL _visible;
    BOOL _wifiBreathing;
    BOOL _wifiActive;
    BOOL _wifiFastAnimation;
}

@end
