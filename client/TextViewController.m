#import "TextViewController.h"
#import "OSPlatform.h"

@implementation TextViewController

- (id)initWithText:(NSString *)text {
    if ((self = [super init])) {
        _text = [text copy];
    }
    return self;
}

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor whiteColor];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _textView = [[UITextView alloc] initWithFrame:view.bounds];
    _textView.editable = NO;
    _textView.scrollEnabled = YES;
    _textView.opaque = NO;
    _textView.backgroundColor = [UIColor whiteColor];
    _textView.font = [UIFont systemFontOfSize:17];
    _textView.textColor = [UIColor blackColor];
    _textView.dataDetectorTypes = UIDataDetectorTypeNone;
    _textView.text = _text;
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:_textView];

    self.view = view;
    [view release];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"receive.text_view_title", nil);

    UIBarButtonItem *copyAll = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"receive.copy_all", nil)
                                                                style:UIBarButtonItemStyleBordered
                                                               target:self
                                                               action:@selector(copyAllTapped:)];
    self.navigationItem.leftBarButtonItem = copyAll;
    [copyAll release];

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
    [_textView setContentOffset:CGPointZero animated:NO];
}

- (void)copyAllTapped:(id)sender {
    [[UIPasteboard generalPasteboard] setString:_text];

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"receive.copied", nil)
                                                    message:nil
                                                   delegate:nil
                                          cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                          otherButtonTitles:nil];
    [alert show];
    [alert release];
}

- (void)doneTapped:(id)sender {
    [self dismissModalViewControllerAnimated:YES];
}

- (void)dealloc {
    [_textView release];
    [_text release];
    [super dealloc];
}

@end
