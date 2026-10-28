#import "OSHUD.h"
#import "OSPlatform.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static UIView *gHUDView = nil;
static UIView *gHUDBox = nil;
static UIActivityIndicatorView *gSpinner = nil;
static UILabel *gTitleLabel = nil;
static UILabel *gMessageLabel = nil;
static UIProgressView *gProgressView = nil;
static UISegmentedControl *gCancelButton = nil;

NSString * const OSHUDDidCancelNotification = @"OSHUDDidCancelNotification";

@interface OSHUD (Private)
+ (void)cancelTapped:(id)sender;
+ (UIView *)targetContainer;
+ (void)layoutBox;
@end

@interface UIWindow (OSRootViewController)
- (UIViewController *)rootViewController;
@end

@implementation OSHUD

+ (UIWindow *)targetWindow {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (window == nil) {
        NSArray *windows = [[UIApplication sharedApplication] windows];
        if ([windows count] > 0) window = [windows objectAtIndex:0];
    }
    return window;
}

+ (UIView *)targetContainer {
    UIWindow *window = [self targetWindow];
    if (window != nil && [window respondsToSelector:@selector(rootViewController)]) {
        UIViewController *root = [window rootViewController];
        if (root != nil && root.view != nil) return root.view;
    }
    return window;
}

+ (void)buildIfNeeded {
    if (gHUDView != nil) return;

    UIView *container = [self targetContainer];
    gHUDView = [[UIView alloc] initWithFrame:container != nil ? container.bounds : [[UIScreen mainScreen] bounds]];
    gHUDView.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.28f];
    gHUDView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    gHUDView.userInteractionEnabled = YES;

    gHUDBox = [[UIView alloc] initWithFrame:CGRectMake((gHUDView.bounds.size.width - 236) / 2,
                                                       (gHUDView.bounds.size.height - 170) / 2,
                                                       236, 170)];
    gHUDBox.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.78f];
    gHUDBox.layer.cornerRadius = 12.0f;
    gHUDBox.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                               UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    gHUDBox.userInteractionEnabled = YES;
    [gHUDView addSubview:gHUDBox];

    gSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    gSpinner.frame = CGRectMake((236 - 37) / 2, 18, 37, 37);
    gSpinner.hidesWhenStopped = NO;
    [gHUDBox addSubview:gSpinner];

    gTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 64, 216, 22)];
    gTitleLabel.backgroundColor = [UIColor clearColor];
    gTitleLabel.font = [UIFont boldSystemFontOfSize:16];
    gTitleLabel.textAlignment = UITextAlignmentCenter;
    gTitleLabel.textColor = [UIColor whiteColor];
    [gHUDBox addSubview:gTitleLabel];

    gMessageLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 87, 216, 22)];
    gMessageLabel.backgroundColor = [UIColor clearColor];
    gMessageLabel.font = OSSmallFont(12);
    gMessageLabel.textAlignment = UITextAlignmentCenter;
    gMessageLabel.textColor = [UIColor colorWithWhite:0.86f alpha:1.0f];
    [gHUDBox addSubview:gMessageLabel];

    gProgressView = [[UIProgressView alloc] initWithFrame:CGRectMake(10, 112, 216, 9)];
    gProgressView.progressViewStyle = UIProgressViewStyleDefault;
    gProgressView.progress = 0.0f;
    gProgressView.hidden = YES;
    [gHUDBox addSubview:gProgressView];

    gCancelButton = [[UISegmentedControl alloc] initWithItems:
                     [NSArray arrayWithObject:NSLocalizedString(@"common.cancel", nil)]];
    gCancelButton.frame = CGRectMake(68, 128, 100, 30);
    gCancelButton.segmentedControlStyle = UISegmentedControlStyleBar;
    gCancelButton.tintColor = [UIColor colorWithWhite:0.22f alpha:1.0f];
    gCancelButton.momentary = YES;
    [gCancelButton addTarget:self action:@selector(cancelTapped:)
            forControlEvents:UIControlEventValueChanged];
    gCancelButton.hidden = YES;
    [gHUDBox addSubview:gCancelButton];

}

+ (void)layoutBox {
    CGFloat boxHeight;

    if (!gProgressView.hidden || !gCancelButton.hidden) {
        boxHeight = 170.0f;
    } else if ([gMessageLabel.text length] == 0) {
        boxHeight = 110.0f;
    } else {
        boxHeight = 130.0f;
    }

    gHUDBox.frame = CGRectMake((gHUDView.bounds.size.width - 236.0f) / 2.0f,
                               (gHUDView.bounds.size.height - boxHeight) / 2.0f,
                               236.0f, boxHeight);
}

+ (void)showWithTitle:(NSString *)title message:(NSString *)message {
    if (![NSThread isMainThread]) {
        NSArray *info = [NSArray arrayWithObjects:title, message, nil];
        [self performSelectorOnMainThread:@selector(showInfo:)
                               withObject:info
                            waitUntilDone:NO];
        return;
    }

    [self buildIfNeeded];
    gTitleLabel.text = title;
    gMessageLabel.text = message;
    gProgressView.hidden = YES;
    gProgressView.progress = 0.0f;
    gCancelButton.hidden = YES;

    if (gHUDView.superview == nil) {
        UIView *container = [self targetContainer];
        if (container == nil) return;
        gHUDView.frame = container.bounds;
        [container addSubview:gHUDView];
    } else if (gHUDView.superview != [self targetContainer]) {
        UIView *container = [self targetContainer];
        [gHUDView removeFromSuperview];
        gHUDView.frame = container.bounds;
        [container addSubview:gHUDView];
    }
    [gHUDView.superview bringSubviewToFront:gHUDView];
    gHUDView.hidden = NO;
    [gSpinner startAnimating];
    [self layoutBox];
}

+ (void)showInfo:(NSArray *)info {
    [self showWithTitle:[info objectAtIndex:0] message:[info objectAtIndex:1]];
}

+ (void)showSaving {
    [self showWithTitle:NSLocalizedString(@"hud.saving_title", nil)
                message:NSLocalizedString(@"hud.saving_message", nil)];
}

+ (void)showSendingTo:(NSString *)alias {
    [self showWithTitle:NSLocalizedString(@"hud.sending_title", nil)
                message:[NSString stringWithFormat:NSLocalizedString(@"hud.sending_message", nil), alias]];
    gProgressView.hidden = NO;
    gProgressView.progress = 0.0f;
    gCancelButton.hidden = NO;
    [self layoutBox];
}

+ (void)showCancelling {
    [self showWithTitle:NSLocalizedString(@"hud.cancelling", nil) message:nil];
}

+ (void)updateSendProgress:(float)progress {
    NSNumber *value = [NSNumber numberWithFloat:progress];
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(setSendProgress:)
                               withObject:value
                            waitUntilDone:NO];
        return;
    }
    [self setSendProgress:value];
}

+ (void)setSendProgress:(NSNumber *)value {
    float progress = [value floatValue];
    if (progress < 0.0f) progress = 0.0f;
    if (progress > 1.0f) progress = 1.0f;
    gProgressView.hidden = NO;
    gProgressView.progress = progress;
    if (progress >= 1.0f) {
        [gSpinner stopAnimating];
    } else {
        [gSpinner startAnimating];
    }
}

+ (void)hide {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(hide) withObject:nil waitUntilDone:NO];
        return;
    }

    [gSpinner stopAnimating];
    gProgressView.hidden = YES;
    gProgressView.progress = 0.0f;
    gCancelButton.hidden = YES;
    [gHUDView removeFromSuperview];
}

+ (void)hideSaving {
    [self hide];
}

+ (void)cancelTapped:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:OSHUDDidCancelNotification
                                                        object:nil];
}

@end
