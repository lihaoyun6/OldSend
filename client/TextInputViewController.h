#import <UIKit/UIKit.h>

@protocol TextInputViewControllerDelegate <NSObject>
- (void)textInputDidFinish:(NSString *)text;
- (void)textInputDidCancel;
@end

@interface TextInputViewController : UIViewController {
    UITextView *_textView;
    id<TextInputViewControllerDelegate> _delegate;
}

@property (nonatomic, assign) id<TextInputViewControllerDelegate> delegate;

@end
