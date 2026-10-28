#import "SettingsViewController.h"
#import "OSPlatform.h"
#import "OSServer.h"

@interface SettingsPatternView : UIView
@end

@implementation SettingsPatternView

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.92f alpha:1.0f];
        self.opaque = YES;
        self.contentMode = UIViewContentModeRedraw;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    UIImage *image = [UIImage imageNamed:@"SettingsBackground.png"];
    CGContextRef context = UIGraphicsGetCurrentContext();

    if (image != nil) {
        CGRect tile = CGRectMake(0, 0, image.size.width, image.size.height);
        CGContextDrawTiledImage(context, tile, image.CGImage);
    } else {
        CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0.92f alpha:1.0f].CGColor);
        CGContextFillRect(context, self.bounds);
    }
}

@end

@implementation SettingsViewController

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.backgroundColor = [UIColor colorWithWhite:0.92f alpha:1.0f];

    {
        SettingsPatternView *background = [[SettingsPatternView alloc] initWithFrame:view.bounds];
        [view addSubview:background];
        [background release];
    }

    _tableView = [[UITableView alloc] initWithFrame:view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.opaque = NO;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:_tableView];

    self.view = view;
    [view release];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"settings.title", nil);
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(serverDidUpdate:)
                                                 name:OSServerDidUpdateNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self layoutTable];
    [_tableView reloadData];
}

- (void)layoutTable {
    CGRect bounds = self.view.bounds;

    if (OSIsPad()) {
        CGFloat width = bounds.size.width - 80.0f;
        if (width > 620.0f) width = 620.0f;
        _tableView.frame = CGRectMake((bounds.size.width - width) / 2.0f, 0,
                                      width, bounds.size.height);
    } else {
        _tableView.frame = bounds;
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if (OSIsPad()) return YES;
    return orientation == UIInterfaceOrientationPortrait;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation
                                         duration:(NSTimeInterval)duration {
    [self layoutTable];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    [self layoutTable];
    [_tableView reloadData];
}

- (void)serverDidUpdate:(NSNotification *)notification {
    /* Reloading the table while the nickname field is being edited removes
       the first responder on iOS 3, which dismisses the keyboard. */
    if ([_nicknameField isFirstResponder]) return;
    [_tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2;
    if (section == 1) return 3;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return NSLocalizedString(@"settings.device_section", nil);
    if (section == 1) return NSLocalizedString(@"settings.network_section", nil);
    return NSLocalizedString(@"settings.about_section", nil);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return nil;
}

- (UITableViewCell *)valueCellWithTitle:(NSString *)title value:(NSString *)value {
    static NSString *identifier = @"ValueCell";
    UITableViewCell *cell = [_tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                       reuseIdentifier:identifier] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.textLabel.text = title;
    cell.detailTextLabel.text = value;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    OSServer *server = [OSServer shared];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            static NSString *identifier = @"NicknameCell";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
            if (cell == nil) {
                cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                               reuseIdentifier:identifier] autorelease];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.textLabel.text = NSLocalizedString(@"settings.nickname", nil);

                _nicknameField = [[UITextField alloc] initWithFrame:CGRectMake(120, 0, 170, 44)];
                _nicknameField.backgroundColor = [UIColor clearColor];
                _nicknameField.font = [UIFont systemFontOfSize:16];
                _nicknameField.textAlignment = UITextAlignmentRight;
                _nicknameField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
                _nicknameField.textColor = [UIColor colorWithRed:0.22f green:0.33f blue:0.53f alpha:1.0f];
                _nicknameField.clearButtonMode = UITextFieldViewModeWhileEditing;
                _nicknameField.returnKeyType = UIReturnKeyDone;
                _nicknameField.autocorrectionType = UITextAutocorrectionTypeNo;
                _nicknameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
                _nicknameField.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
                _nicknameField.delegate = self;
                _nicknameField.tag = 100;
                [cell.contentView addSubview:_nicknameField];

                _randomButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
                _randomButton.frame = CGRectMake(0, 10, 24, 24);
                [_randomButton setImage:[UIImage imageNamed:@"RandomAlias.png"]
                               forState:UIControlStateNormal];
                _randomButton.showsTouchWhenHighlighted = YES;
                [_randomButton addTarget:self
                                  action:@selector(randomNicknameTapped:)
                        forControlEvents:UIControlEventTouchUpInside];
                _randomButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
                _randomButton.tag = 101;
                [cell.contentView addSubview:_randomButton];
            } else {
                _nicknameField = (UITextField *)[cell.contentView viewWithTag:100];
                _randomButton = (UIButton *)[cell.contentView viewWithTag:101];
            }
            _nicknameField.text = [server alias];
            {
                CGFloat cellWidth = cell.contentView.bounds.size.width;
                _nicknameField.frame = CGRectMake(cellWidth - 190, 0, 148, 44);
                _randomButton.frame = CGRectMake(cellWidth - 34, 10, 24, 24);
            }
            return cell;
        }

        {
            static NSString *identifier = @"QuickSaveCell";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
            if (cell == nil) {
                cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                               reuseIdentifier:identifier] autorelease];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.textLabel.text = NSLocalizedString(@"settings.quick_save", nil);

                _quickSaveSwitch = [[UISwitch alloc] init];
                [_quickSaveSwitch addTarget:self
                                     action:@selector(quickSaveChanged:)
                           forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = _quickSaveSwitch;
            }
            _quickSaveSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"quick_save"];
            return cell;
        }
    }

    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            return [self valueCellWithTitle:NSLocalizedString(@"settings.listen_address", nil)
                                      value:[NSString stringWithFormat:@"%@:%d",
                                             [server localIP], [server port]]];
        }
        if (indexPath.row == 1) {
            return [self valueCellWithTitle:NSLocalizedString(@"settings.protocol", nil)
                                      value:NSLocalizedString(@"settings.protocol_value", nil)];
        }
        {
            static NSString *identifier = @"AnnounceCell";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
            if (cell == nil) {
                cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                               reuseIdentifier:identifier] autorelease];
                cell.textLabel.text = NSLocalizedString(@"settings.announce", nil);
                cell.textLabel.textColor = [UIColor colorWithRed:0.0f green:0.32f blue:0.65f alpha:1.0f];
            }
            return cell;
        }
    }

    {
        NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
        return [self valueCellWithTitle:NSLocalizedString(@"settings.version", nil)
                                  value:[NSString stringWithFormat:@"v%@", version != nil ? version : @"1.0.0"]];
    }
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0 && _nicknameField != nil) {
        CGFloat cellWidth = cell.contentView.bounds.size.width;
        _nicknameField.frame = CGRectMake(cellWidth - 190.0f, 0, 148.0f, 44.0f);
        _randomButton.frame = CGRectMake(cellWidth - 34.0f, 10.0f, 24.0f, 24.0f);
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 2) {
        [[OSServer shared] announceNow];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"settings.announce", nil)
                                                        message:NSLocalizedString(@"settings.announce_done", nil)
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                              otherButtonTitles:nil];
        [alert show];
        [alert release];
    }
}

- (void)randomNicknameTapped:(id)sender {
    OSServer *server = [OSServer shared];
    NSString *alias = [OSServer generateAlias];
    int i;

    for (i = 0; i < 5 && [alias isEqualToString:[server alias]]; i++) {
        alias = [OSServer generateAlias];
    }

    _nicknameField.text = alias;
    [server setAlias:alias];
}

- (void)quickSaveChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"quick_save"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self applyNickname];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    [self applyNickname];
}

- (void)applyNickname {
    NSString *text = [_nicknameField.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text length] == 0) {
        _nicknameField.text = [[OSServer shared] alias];
        return;
    }
    [[OSServer shared] setAlias:text];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_tableView release];
    [_nicknameField release];
    [_randomButton release];
    [_quickSaveSwitch release];
    [super dealloc];
}

@end
