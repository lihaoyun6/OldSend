#import "ReceiveViewController.h"
#import "OSServer.h"
#import "OSPlatform.h"
#import "OSNavigationController.h"
#import "TextViewController.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@implementation ReceiveViewController

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor whiteColor];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _wifiView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ReceiveWifiLarge.png"]];
    _wifiView.contentMode = UIViewContentModeCenter;
    _wifiView.frame = CGRectMake((frame.size.width - 160) / 2, 18, 160, 160);
    _wifiView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [view addSubview:_wifiView];

    _wifiBlueView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ReceiveWifiLargeBlue.png"]];
    _wifiBlueView.contentMode = UIViewContentModeCenter;
    _wifiBlueView.frame = _wifiView.frame;
    _wifiBlueView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _wifiBlueView.alpha = 1.0f;
    [view addSubview:_wifiBlueView];

    _nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 200, frame.size.width - 40, 40)];
    _nameLabel.backgroundColor = [UIColor clearColor];
    _nameLabel.font = [UIFont boldSystemFontOfSize:23];
    _nameLabel.textColor = [UIColor colorWithWhite:0.24f alpha:1.0f];
    _nameLabel.adjustsFontSizeToFitWidth = YES;
    _nameLabel.minimumFontSize = 14;
    _nameLabel.textAlignment = UITextAlignmentCenter;
    [view addSubview:_nameLabel];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 246, frame.size.width - 40, 20)];
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.font = OSSmallFont(12);
    _statusLabel.textAlignment = UITextAlignmentCenter;
    _statusLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
    _statusLabel.adjustsFontSizeToFitWidth = YES;
    _statusLabel.minimumFontSize = 9;
    [view addSubview:_statusLabel];

    _progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(30, 274, frame.size.width - 60, 9)];
    _progressView.progressViewStyle = UIProgressViewStyleDefault;
    _progressView.hidden = YES;
    _progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [view addSubview:_progressView];

    _progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 288, frame.size.width - 40, 16)];
    _progressLabel.backgroundColor = [UIColor clearColor];
    _progressLabel.font = OSSmallFont(11);
    _progressLabel.textAlignment = UITextAlignmentCenter;
    _progressLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
    _progressLabel.hidden = YES;
    _progressLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [view addSubview:_progressLabel];

    _footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, frame.size.height - 36,
                                                             frame.size.width - 40, 24)];
    _footerLabel.backgroundColor = [UIColor clearColor];
    _footerLabel.font = OSSmallFont(11);
    _footerLabel.textAlignment = UITextAlignmentCenter;
    _footerLabel.textColor = [UIColor colorWithWhite:0.55f alpha:1.0f];
    _footerLabel.text = NSLocalizedString(@"receive.footer", nil);
    _footerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [view addSubview:_footerLabel];

    self.view = view;
    [view release];

    [self layoutContent];
}

- (void)layoutContent {
    CGRect bounds = self.view.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;

    if (OSIsPad()) {
        CGFloat iconSize = 320.0f;
        CGFloat iconY = (height > 800.0f) ? 110.0f : 40.0f;
        CGFloat nameY = iconY + iconSize + 36.0f;
        CGFloat progressWidth = width - 240.0f;
        if (progressWidth > 560.0f) progressWidth = 560.0f;

        _wifiView.image = [UIImage imageNamed:@"ReceiveWifiLarge-iPad.png"];
        _wifiBlueView.image = [UIImage imageNamed:@"ReceiveWifiLargeBlue-iPad.png"];
        _wifiView.frame = CGRectMake((width - iconSize) / 2, iconY, iconSize, iconSize);
        _wifiBlueView.frame = _wifiView.frame;
        _nameLabel.frame = CGRectMake(40, nameY, width - 80, 52);
        _statusLabel.frame = CGRectMake(40, nameY + 58, width - 80, 26);
        _progressView.frame = CGRectMake((width - progressWidth) / 2, nameY + 104,
                                         progressWidth, 12);
        _progressLabel.frame = CGRectMake(40, nameY + 124, width - 80, 20);
        _footerLabel.frame = CGRectMake(20, height - 44, width - 40, 24);

        _nameLabel.font = [UIFont boldSystemFontOfSize:34];
        _nameLabel.minimumFontSize = 20;
        _statusLabel.font = OSSmallFont(16);
        _statusLabel.minimumFontSize = 12;
        _progressLabel.font = OSSmallFont(14);
        _footerLabel.font = OSSmallFont(13);
    } else {
        _wifiView.image = [UIImage imageNamed:@"ReceiveWifiLarge.png"];
        _wifiBlueView.image = [UIImage imageNamed:@"ReceiveWifiLargeBlue.png"];
        _wifiView.frame = CGRectMake((width - 160) / 2, 18, 160, 160);
        _wifiBlueView.frame = _wifiView.frame;
        _nameLabel.frame = CGRectMake(20, 200, width - 40, 40);
        _statusLabel.frame = CGRectMake(20, 246, width - 40, 20);
        _progressView.frame = CGRectMake(30, 274, width - 60, 9);
        _progressLabel.frame = CGRectMake(20, 288, width - 40, 16);
        _footerLabel.frame = CGRectMake(20, height - 36, width - 40, 24);

        _nameLabel.font = [UIFont boldSystemFontOfSize:23];
        _nameLabel.minimumFontSize = 14;
        _statusLabel.font = OSSmallFont(12);
        _statusLabel.minimumFontSize = 9;
        _progressLabel.font = OSSmallFont(11);
        _footerLabel.font = OSSmallFont(11);
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if (OSIsPad()) return YES;
    return orientation == UIInterfaceOrientationPortrait;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation
                                         duration:(NSTimeInterval)duration {
    [self layoutContent];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    [self layoutContent];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"tab.receive", nil);
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(serverDidUpdate:)
                                                 name:OSServerDidUpdateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textReceived:)
                                                 name:OSServerDidReceiveTextNotification
                                               object:nil];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _visible = YES;
    [self layoutContent];
    [self refresh];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
    [self stopWifiBreathing];
}

- (void)startWifiBreathing {
    BOOL fast = _wifiActive;

    if (!_visible) return;
    if (_wifiBreathing && _wifiFastAnimation == fast) return;

    _wifiBreathing = YES;
    _wifiFastAnimation = fast;
    [_wifiBlueView.layer removeAllAnimations];

    {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        animation.fromValue = [NSNumber numberWithFloat:1.0f];
        animation.toValue = [NSNumber numberWithFloat:0.0f];
        animation.duration = fast ? 0.5 : 1.8;
        animation.autoreverses = YES;
        animation.repeatCount = HUGE_VALF;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        animation.removedOnCompletion = NO;
        [_wifiBlueView.layer addAnimation:animation forKey:@"wifiBreathing"];
    }
}

- (void)stopWifiBreathing {
    _wifiBreathing = NO;
    _wifiFastAnimation = NO;
    [_wifiBlueView.layer removeAllAnimations];
    _wifiBlueView.alpha = 1.0f;
}

- (void)serverDidUpdate:(NSNotification *)notification {
    [self refresh];
}

- (void)textReceived:(NSNotification *)notification {
    NSString *text = [[notification userInfo] objectForKey:@"text"];
    TextViewController *controller;
    UINavigationController *navigation;
    UIViewController *presenter;

    if ([text length] == 0) return;

    controller = [[TextViewController alloc] initWithText:text];
    navigation = [[OSNavigationController alloc] initWithRootViewController:controller];

    presenter = self.tabBarController != nil ? self.tabBarController : self;
    if (presenter.modalViewController != nil) {
        presenter = presenter.modalViewController;
    }
    [presenter presentModalViewController:navigation animated:YES];

    [controller release];
    [navigation release];
}

- (void)refresh {
    OSServer *server = [OSServer shared];
    NSString *alias = [server alias];
    BOOL active = [server isSessionActive] || [server isReceiving] || [server isSavingToPhotos];

    _wifiActive = active;
    if (!_visible) {
        [self stopWifiBreathing];
    } else {
        [self startWifiBreathing];
    }
    _nameLabel.text = alias;

    _statusLabel.text = [server receiveStatus];

    {
        BOOL receiving = [server isSessionActive] || [server isReceiving];
        _progressView.hidden = !receiving;
        _progressLabel.hidden = !receiving;
        if (receiving) {
            float progress = [server uploadProgress];
            _progressView.progress = progress;
            _progressLabel.text = [NSString stringWithFormat:@"%d%%",
                                   (int)(progress * 100.0f)];
        }
    }

    _statusLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_wifiView release];
    [_wifiBlueView release];
    [_nameLabel release];
    [_statusLabel release];
    [_progressView release];
    [_progressLabel release];
    [_footerLabel release];
    [super dealloc];
}

@end
