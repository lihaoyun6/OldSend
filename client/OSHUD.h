#import <Foundation/Foundation.h>

extern NSString * const OSHUDDidCancelNotification;

@interface OSHUD : NSObject

+ (void)showSaving;
+ (void)showSendingTo:(NSString *)alias;
+ (void)showCancelling;
+ (void)updateSendProgress:(float)progress;
+ (void)hide;
+ (void)hideSaving;

@end
