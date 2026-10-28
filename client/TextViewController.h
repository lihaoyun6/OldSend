#import <UIKit/UIKit.h>

@interface TextViewController : UIViewController {
    UITextView *_textView;
    NSString *_text;
}

- (id)initWithText:(NSString *)text;

@end
