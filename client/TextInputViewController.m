#import "TextInputViewController.h"
#import "OSPlatform.h"

@implementation TextInputViewController

@synthesize delegate = _delegate;

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor whiteColor];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _textView = [[UITextView alloc] initWithFrame:view.bounds];
    _textView.backgroundColor = [UIColor whiteColor];
    _textView.font = [UIFont systemFontOfSize:17];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:_textView];

    self.view = view;
    [view release];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"send.text_title", nil);

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                           target:self
                                                                           action:@selector(cancelTapped:)];
    self.navigationItem.leftBarButtonItem = cancel;
    [cancel release];

    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                         target:self
                                                                         action:@selector(doneTapped:)];
    self.navigationItem.rightBarButtonItem = done;
    [done release];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if (OSIsPad()) return YES;
    return orientation == UIInterfaceOrientationPortrait;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_textView becomeFirstResponder];
}

- (void)cancelTapped:(id)sender {
    if ([_delegate respondsToSelector:@selector(textInputDidCancel)]) {
        [_delegate textInputDidCancel];
    }
    [self dismissModalViewControllerAnimated:YES];
}

- (void)doneTapped:(id)sender {
    if ([_delegate respondsToSelector:@selector(textInputDidFinish:)]) {
        [_delegate textInputDidFinish:_textView.text];
    }
    [self dismissModalViewControllerAnimated:YES];
}

- (void)dealloc {
    [_textView release];
    [super dealloc];
}

@end
