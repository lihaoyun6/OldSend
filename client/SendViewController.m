#import "SendViewController.h"
#import "OSServer.h"
#import "OSPlatform.h"
#import "OSNavigationController.h"
#import "OSHUD.h"
#import "MediaPickerLoader.h"
#include <math.h>

/* iPhoneOS 3.1.3 SDK predates the iPad; UIPopoverController is declared here
   and only instantiated via NSClassFromString on iPad at runtime. */
@interface UIPopoverController : NSObject
- (id)initWithContentViewController:(UIViewController *)viewController;
- (void)presentPopoverFromRect:(CGRect)rect
                        inView:(UIView *)view
      permittedArrowDirections:(NSUInteger)arrowDirections
                      animated:(BOOL)animated;
- (void)dismissPopoverAnimated:(BOOL)animated;
@property (nonatomic, assign) id delegate;
@end

@interface UIActionSheet (OSPad)
- (void)showFromBarButtonItem:(UIBarButtonItem *)item animated:(BOOL)animated;
@end

@interface DeviceCell : UITableViewCell {
    UIImageView *_deviceIconView;
    UILabel *_nameLabel;
    UILabel *_detailLabel;
    UIButton *_detailButton;
}
- (void)setDevice:(NSDictionary *)device;
- (UIButton *)detailButton;
@end

@implementation DeviceCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _deviceIconView = [[UIImageView alloc] init];
        _deviceIconView.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:_deviceIconView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.backgroundColor = [UIColor clearColor];
        _nameLabel.font = [UIFont boldSystemFontOfSize:17];
        _nameLabel.textColor = [UIColor blackColor];
        [self.contentView addSubview:_nameLabel];

        _detailLabel = [[UILabel alloc] init];
        _detailLabel.backgroundColor = [UIColor clearColor];
        _detailLabel.font = OSSmallFont(12);
        _detailLabel.textColor = [UIColor grayColor];
        [self.contentView addSubview:_detailLabel];

        _detailButton = [[UIButton buttonWithType:UIButtonTypeDetailDisclosure] retain];
        self.accessoryView = _detailButton;
    }
    return self;
}

- (UIButton *)detailButton {
    return _detailButton;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    CGFloat top = floorf((bounds.size.height - 42.0f) / 2.0f);

    _deviceIconView.frame = CGRectMake(10, floorf((bounds.size.height - 44.0f) / 2.0f), 44, 44);
    _nameLabel.frame = CGRectMake(64, top, bounds.size.width - 70, 24);
    _detailLabel.frame = CGRectMake(64, top + 24, bounds.size.width - 70, 18);
}

- (void)setDevice:(NSDictionary *)device {
    NSString *type = [[device objectForKey:@"type"] lowercaseString];
    NSString *iconName = @"DeviceDesktop.png";
    NSString *protocol = [[device objectForKey:@"protocol"] uppercaseString];
    NSString *model = [device objectForKey:@"model"];

    if ([type isEqualToString:@"mobile"]) {
        iconName = @"DeviceMobile.png";
    } else if ([type isEqualToString:@"web"]) {
        iconName = @"DeviceWeb.png";
    } else if ([type isEqualToString:@"headless"]) {
        iconName = @"DeviceHeadless.png";
    } else if ([type isEqualToString:@"server"]) {
        iconName = @"DeviceServer.png";
    }

    if ([protocol length] == 0) protocol = @"HTTPS";
    if ([model length] == 0) {
        NSArray *parts = [[device objectForKey:@"ip"] componentsSeparatedByString:@"."];
        model = [NSString stringWithFormat:@"#%@", [parts lastObject]];
    }

    _deviceIconView.image = [UIImage imageNamed:iconName];
    _nameLabel.text = [device objectForKey:@"alias"];
    _detailLabel.text = [NSString stringWithFormat:@"%@ · %@", protocol, model];
}

- (void)dealloc {
    [_deviceIconView release];
    [_nameLabel release];
    [_detailLabel release];
    [_detailButton release];
    [super dealloc];
}

@end

@implementation SendViewController

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor whiteColor];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _tableView = [[UITableView alloc] initWithFrame:view.bounds style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = OSIsPad() ? 76.0f : 62.0f;
    _tableView.allowsSelectionDuringEditing = YES;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:_tableView];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 150, frame.size.width - 40, 60)];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.font = OSSmallFont(13);
    _emptyLabel.textAlignment = UITextAlignmentCenter;
    _emptyLabel.textColor = [UIColor grayColor];
    _emptyLabel.numberOfLines = 2;
    _emptyLabel.text = NSLocalizedString(@"send.searching", nil);
    [view addSubview:_emptyLabel];

    self.view = view;
    [view release];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"send.title", nil);
    _pendingItems = [[NSMutableArray alloc] init];

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                            target:self
                                                                            action:@selector(refreshTapped:)];
    self.navigationItem.leftBarButtonItem = refresh;
    [refresh release];

    _addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                               target:self
                                                               action:@selector(addTapped:)];
    self.navigationItem.rightBarButtonItem = _addButton;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(serverDidUpdate:)
                                                 name:OSServerDidUpdateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sendDidFinish:)
                                                 name:OSServerSendDidFinishNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sendProgress:)
                                                 name:OSServerSendProgressNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(hudCancel:)
                                                 name:OSHUDDidCancelNotification
                                               object:nil];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _tableView.frame = self.view.bounds;
    _emptyLabel.frame = CGRectMake(40, OSIsPad() ? self.view.bounds.size.height * 0.3f : 150,
                                   self.view.bounds.size.width - 80, 60);
    [self refresh];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if (OSIsPad()) return YES;
    return orientation == UIInterfaceOrientationPortrait;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation
                                         duration:(NSTimeInterval)duration {
    _tableView.frame = self.view.bounds;
    _emptyLabel.frame = CGRectMake(40, self.view.bounds.size.height * 0.3f,
                                   self.view.bounds.size.width - 80, 60);
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    _tableView.frame = self.view.bounds;
    _emptyLabel.frame = CGRectMake(40, self.view.bounds.size.height * 0.3f,
                                   self.view.bounds.size.width - 80, 60);
}

- (void)serverDidUpdate:(NSNotification *)notification {
    if ([self hasPending]) {
        [self refreshDeviceSection];
        return;
    }
    [self refresh];
}

- (void)refreshTapped:(id)sender {
    [[OSServer shared] announceNow];
    [[OSServer shared] refreshDevices];
    if ([self hasPending]) {
        [self refreshDeviceSection];
    } else {
        [self refresh];
    }
}

- (void)addTapped:(id)sender {
    if (_typeSheet != nil) return;

    _typeSheet = [[UIActionSheet alloc] initWithTitle:nil
                                            delegate:self
                                   cancelButtonTitle:NSLocalizedString(@"common.cancel", nil)
                              destructiveButtonTitle:nil
                                   otherButtonTitles:NSLocalizedString(@"send.media", nil),
                                                     NSLocalizedString(@"send.files", nil),
                                                     NSLocalizedString(@"send.text", nil),
                                                     NSLocalizedString(@"send.clipboard", nil),
                                                     nil];
    if (OSIsPad()) {
        [_typeSheet showFromBarButtonItem:_addButton animated:YES];
    } else if (self.tabBarController != nil) {
        [_typeSheet showFromTabBar:self.tabBarController.tabBar];
    } else {
        [_typeSheet showInView:self.view];
    }
}

- (void)runAddType:(NSNumber *)type {
    NSInteger value = [type integerValue];

    if (value == 0) {
        [self chooseMedia];
    } else if (value == 1) {
        [self chooseFile];
    } else if (value == 2) {
        [self enterText];
    } else if (value == 3) {
        [self readClipboard];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    [_typeSheet release];
    _typeSheet = nil;
    [self runAddType:[NSNumber numberWithInteger:buttonIndex]];
}

- (void)chooseFile {
    SendFilePickerViewController *picker = [[SendFilePickerViewController alloc] init];
    UINavigationController *navigation = [[OSNavigationController alloc] initWithRootViewController:picker];
    picker.delegate = self;
    [self presentModalViewController:navigation animated:YES];
    [picker release];
    [navigation release];
}

- (void)sendFilePicker:(SendFilePickerViewController *)picker
         didSelectFile:(NSString *)path
                  name:(NSString *)name
                  size:(long long)size {
    [_pendingItems addObject:[NSDictionary dictionaryWithObjectsAndKeys:
        @"file", @"kind",
        path, @"path",
        name, @"name",
        @"application/octet-stream", @"type",
        [NSNumber numberWithLongLong:size], @"size", nil]];
    [self refresh];
}

- (void)sendFilePickerDidCancel:(SendFilePickerViewController *)picker {
}

- (UIView *)popoverAnchorView {
    UINavigationBar *bar = self.navigationController.navigationBar;
    return bar != nil ? bar : self.view;
}

- (CGRect)popoverAnchorRectInView:(UIView *)view {
    return CGRectMake(view.bounds.size.width - 60.0f,
                      view.bounds.size.height - 22.0f,
                      60.0f, 22.0f);
}

- (void)chooseMedia {
    Class mediaPickerClass = OSLoadMediaPickerClass();

    if (mediaPickerClass != nil) {
        MediaPickerViewController *picker =
            (MediaPickerViewController *)[[mediaPickerClass alloc] init];
        UINavigationController *navigation =
            [[OSNavigationController alloc] initWithRootViewController:picker];

        picker.delegate = self;
        [self presentModalViewController:navigation animated:YES];
        [picker release];
        [navigation release];
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.allowsEditing = NO;

    if (OSIsPad()) {
        Class popoverClass = NSClassFromString(@"UIPopoverController");
        if (popoverClass != nil) {
            UIPopoverController *popover;
            UIView *anchorView;

            popover = [[popoverClass alloc] initWithContentViewController:picker];
            popover.delegate = self;
            _mediaPopover = [popover retain];

            anchorView = [self popoverAnchorView];
            [popover presentPopoverFromRect:[self popoverAnchorRectInView:anchorView]
                                    inView:anchorView
                  permittedArrowDirections:1 /* Up */
                                  animated:YES];

            [popover release];
            [picker release];
            return;
        }
    }

    [self presentModalViewController:picker animated:YES];
    [picker release];
}

- (void)dismissMediaPicker {
    if (_mediaPopover != nil) {
        UIPopoverController *popover = (UIPopoverController *)_mediaPopover;
        popover.delegate = nil;
        [popover dismissPopoverAnimated:YES];
        [_mediaPopover release];
        _mediaPopover = nil;
    } else {
        [self dismissModalViewControllerAnimated:YES];
    }
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popover {
    if (popover == (UIPopoverController *)_mediaPopover) {
        [_mediaPopover release];
        _mediaPopover = nil;
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker
        didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = [info objectForKey:UIImagePickerControllerOriginalImage];

    [self dismissMediaPicker];

    if (image != nil) {
        [self addMediaImage:image];
        [self refresh];
    } else {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"send.media", nil)
                                                        message:NSLocalizedString(@"send.media_failed_message", nil)
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                              otherButtonTitles:nil];
        [alert show];
        [alert release];
    }
}

- (UIImage *)resizedImage:(UIImage *)image maxDimension:(CGFloat)maxDimension {
    CGSize size = image.size;
    CGSize target;
    CGFloat scale = 1.0f;
    UIImage *result;

    if (size.width < 1.0f || size.height < 1.0f) return nil;
    if (size.width > maxDimension || size.height > maxDimension) {
        scale = maxDimension / MAX(size.width, size.height);
    }
    target = CGSizeMake(floorf(size.width * scale), floorf(size.height * scale));
    if (target.width < 1.0f) target.width = 1.0f;
    if (target.height < 1.0f) target.height = 1.0f;

    UIGraphicsBeginImageContext(target);
    [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (void)addMediaImage:(UIImage *)image {
    UIImage *resized;
    NSData *data;
    NSString *directory;
    NSString *path;

    if (image == nil) return;
    resized = [self resizedImage:image maxDimension:800.0f];
    data = UIImageJPEGRepresentation(resized != nil ? resized : image, 0.9f);
    if (data == nil) return;

    directory = @"/var/mobile/Library/OldSend/Outgoing";
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    path = [directory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"media-%u-%u.jpg",
             (unsigned)[[NSDate date] timeIntervalSince1970],
             (unsigned)arc4random()]];
    [data writeToFile:path atomically:YES];
    [_pendingItems addObject:[NSDictionary dictionaryWithObjectsAndKeys:
        @"media", @"kind",
        path, @"path",
        [path lastPathComponent], @"name",
        @"image/jpeg", @"type",
        [NSNumber numberWithUnsignedInteger:[data length]], @"size", nil]];
}

- (void)mediaPicker:(id)picker didFinishWithItems:(NSArray *)items {
    NSString *directory = @"/var/mobile/Library/OldSend/Outgoing";

    [self dismissModalViewControllerAnimated:YES];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    for (NSDictionary *item in items) {
        NSString *kind = [item objectForKey:@"kind"];
        if ([kind isEqualToString:@"image"]) {
            [self addMediaImage:[item objectForKey:@"image"]];
        } else if ([kind isEqualToString:@"video"]) {
            NSString *source = [item objectForKey:@"path"];
            NSString *name = [item objectForKey:@"name"];
            NSString *destination = [directory stringByAppendingPathComponent:name];

            if ([[NSFileManager defaultManager] moveItemAtPath:source
                                                        toPath:destination
                                                         error:NULL]) {
                [_pendingItems addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    @"media", @"kind",
                    destination, @"path",
                    name, @"name",
                    [item objectForKey:@"type"], @"type",
                    [item objectForKey:@"size"], @"size", nil]];
            }
        }
    }
    [self refresh];
}

- (void)mediaPickerDidCancel:(id)picker {
    [self dismissModalViewControllerAnimated:YES];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissMediaPicker];
}

- (void)enterText {
    TextInputViewController *controller = [[TextInputViewController alloc] init];
    UINavigationController *navigation = [[OSNavigationController alloc] initWithRootViewController:controller];
    controller.delegate = self;
    [self presentModalViewController:navigation animated:YES];
    [controller release];
    [navigation release];
}

- (void)textInputDidFinish:(NSString *)text {
    if ([text length] == 0) return;
    [_pendingItems addObject:[NSDictionary dictionaryWithObjectsAndKeys:
        @"text", @"kind", text, @"text", nil]];
    [self refresh];
}

- (void)textInputDidCancel {
}

- (void)readClipboard {
    NSString *text = [[UIPasteboard generalPasteboard] string];
    if ([text length] == 0) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"send.clipboard_empty_title", nil)
                                                        message:NSLocalizedString(@"send.clipboard_empty_message", nil)
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                              otherButtonTitles:nil];
        [alert show];
        [alert release];
        return;
    }

    [_pendingItems addObject:[NSDictionary dictionaryWithObjectsAndKeys:
        @"text", @"kind", text, @"text", nil]];
    [self refresh];
}

- (BOOL)hasPending {
    return [_pendingItems count] > 0;
}

- (NSString *)formatBytes:(long long)bytes {
    if (bytes < 1024) {
        return [NSString stringWithFormat:@"%lld B", bytes];
    } else if (bytes < 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f KB", (double)bytes / 1024.0];
    } else if (bytes < 1024LL * 1024LL * 1024LL) {
        return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
    }
    return [NSString stringWithFormat:@"%.2f GB", (double)bytes / (1024.0 * 1024.0 * 1024.0)];
}

- (NSString *)pendingSummary {
    int mediaCount = 0;
    int fileCount = 0;
    int textCount = 0;
    int textCharacters = 0;
    long long mediaBytes = 0;
    long long fileBytes = 0;

    for (NSDictionary *item in _pendingItems) {
        NSString *kind = [item objectForKey:@"kind"];
        if ([kind isEqualToString:@"media"]) {
            mediaCount++;
            mediaBytes += [[item objectForKey:@"size"] longLongValue];
        } else if ([kind isEqualToString:@"file"]) {
            fileCount++;
            fileBytes += [[item objectForKey:@"size"] longLongValue];
        } else {
            textCount++;
            textCharacters += (int)[[item objectForKey:@"text"] length];
        }
    }

    if (mediaCount > 0 && fileCount == 0 && textCount == 0) {
        return [NSString stringWithFormat:NSLocalizedString(@"send.pending_media", nil),
                mediaCount, [self formatBytes:mediaBytes]];
    }
    if (fileCount > 0 && mediaCount == 0 && textCount == 0) {
        return [NSString stringWithFormat:NSLocalizedString(@"send.pending_files", nil),
                fileCount, [self formatBytes:fileBytes]];
    }
    if (textCount > 0 && mediaCount == 0 && fileCount == 0) {
        if (textCount == 1) {
            return [NSString stringWithFormat:NSLocalizedString(@"send.pending_text", nil),
                    textCharacters];
        }
        return [NSString stringWithFormat:NSLocalizedString(@"send.pending_texts", nil),
                textCount, textCharacters];
    }

    {
        NSMutableArray *parts = [NSMutableArray array];
        NSMutableString *summary = [NSMutableString string];

        if (mediaCount > 0) {
            [parts addObject:[NSString stringWithFormat:
                              NSLocalizedString(@"send.count_media", nil), mediaCount]];
        }
        if (fileCount > 0) {
            [parts addObject:[NSString stringWithFormat:
                              NSLocalizedString(@"send.count_files", nil), fileCount]];
        }
        if (textCount > 0) {
            [parts addObject:[NSString stringWithFormat:
                              NSLocalizedString(@"send.count_texts", nil), textCount]];
        }
        [summary appendString:[parts componentsJoinedByString:
                                NSLocalizedString(@"common.list_separator", nil)]];
        [summary appendString:NSLocalizedString(@"send.pending_suffix", nil)];
        return summary;
    }
}

- (void)clearPending {
    [_pendingItems removeAllObjects];
}

- (void)refreshDeviceSection {
    [self updateDeviceSummary];
    if ([_tableView numberOfSections] > 1) {
        [_tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                  withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)updateDeviceSummary {
    NSUInteger count = [[[OSServer shared] devices] count];
    _emptyLabel.hidden = (count > 0);
    _addButton.enabled = (count > 0);
    _tableView.separatorStyle = count > 0 ? UITableViewCellSeparatorStyleSingleLine
                                          : UITableViewCellSeparatorStyleNone;
}

- (void)refresh {
    BOOL editing = [self hasPending];

    [_tableView reloadData];
    if (_tableView.editing != editing) {
        [_tableView setEditing:editing animated:NO];
    }
    [self updateDeviceSummary];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self hasPending] ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self hasPending] && section == 0) return nil;
    if ([[[OSServer shared] devices] count] == 0) return nil;
    return NSLocalizedString(@"send.nearby", nil);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self hasPending] && section == 0) return 1;
    return (NSInteger)[[[OSServer shared] devices] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self hasPending] && indexPath.section == 0) return OSIsPad() ? 44.0f : 40.0f;
    return OSIsPad() ? 76.0f : 62.0f;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self hasPending] && indexPath.section == 0;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self hasPending] && indexPath.section == 0) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView
        commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
         forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete &&
        [self hasPending] && indexPath.section == 0) {
        [self clearPending];
        [tableView reloadData];
        [self refresh];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self hasPending] && indexPath.section == 0) {
        static NSString *summaryIdentifier = @"PendingCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:summaryIdentifier];
        if (cell == nil) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:summaryIdentifier] autorelease];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.font = OSSmallFont(13);
            cell.textLabel.textColor = [UIColor colorWithWhite:0.35f alpha:1.0f];
        }
        cell.textLabel.text = [self pendingSummary];
        return cell;
    }

    static NSString *identifier = @"DeviceCell";
    DeviceCell *cell = (DeviceCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[[DeviceCell alloc] initWithStyle:UITableViewCellStyleDefault
                                  reuseIdentifier:identifier] autorelease];
    }

    [cell setDevice:[[[OSServer shared] devices] objectAtIndex:indexPath.row]];
    {
        UIButton *button = [cell detailButton];
        [button removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [button addTarget:self action:@selector(detailTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        button.tag = indexPath.row;
    }
    return cell;
}

- (void)detailTapped:(UIButton *)sender {
    NSArray *devices = [[OSServer shared] devices];
    NSUInteger row = (NSUInteger)sender.tag;
    NSDictionary *device;
    NSString *version;
    NSString *message;

    if (row >= [devices count]) return;
    device = [devices objectAtIndex:row];

    version = [device objectForKey:@"version"];
    if ([version length] == 0) version = @"2.2";

    message = [NSString stringWithFormat:@"%@\n%@\n%@:%@",
               [device objectForKey:@"alias"],
               [NSString stringWithFormat:NSLocalizedString(@"send.protocol_version", nil),
                version],
               [device objectForKey:@"ip"], [device objectForKey:@"port"]];

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"send.device_details", nil)
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                          otherButtonTitles:nil];
    [alert show];
    [alert release];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ([self hasPending] && indexPath.section == 0) return;

    {
        NSArray *devices = [[OSServer shared] devices];
        NSDictionary *device;
        if (indexPath.row >= (NSInteger)[devices count]) return;
        device = [devices objectAtIndex:indexPath.row];

        if (![self hasPending]) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"send.select_first_title", nil)
                                                            message:NSLocalizedString(@"send.select_first_message", nil)
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                                  otherButtonTitles:nil];
            [alert show];
            [alert release];
            return;
        }

        [self sendToDevice:device];
    }
}

- (void)sendToDevice:(NSDictionary *)device {
    NSArray *items;

    if ([_pendingItems count] == 0) return;
    items = [NSArray arrayWithArray:_pendingItems];

    _tableView.userInteractionEnabled = NO;
    [OSHUD showSendingTo:[device objectForKey:@"alias"]];
    [[OSServer shared] sendItems:items toDevice:device];
}

- (void)sendProgress:(NSNotification *)notification {
    NSNumber *value = [[notification userInfo] objectForKey:@"progress"];
    [OSHUD updateSendProgress:[value floatValue]];
}

- (void)hudCancel:(NSNotification *)notification {
    [[OSServer shared] cancelSending];
    [OSHUD showCancelling];
}

- (void)sendDidFinish:(NSNotification *)notification {
    NSDictionary *result = [notification userInfo];
    BOOL success = [[result objectForKey:@"success"] boolValue];
    BOOL cancelled = [[result objectForKey:@"cancelled"] boolValue];
    NSString *alias = [result objectForKey:@"alias"];
    UIAlertView *alert;

    [OSHUD hideSaving];
    _tableView.userInteractionEnabled = YES;

    if (cancelled) {
        alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"send.cancelled_title", nil)
                                           message:NSLocalizedString(@"send.cancelled_message", nil)
                                          delegate:nil
                                 cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                 otherButtonTitles:nil];
    } else if (success) {
        [self clearPending];
        [self refresh];
        alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"send.success_title", nil)
                                           message:[NSString stringWithFormat:
                                                    NSLocalizedString(@"send.success_message", nil), alias]
                                          delegate:nil
                                 cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                 otherButtonTitles:nil];
    } else {
        NSString *message = [result objectForKey:@"message"];
        if ([message length] == 0) message = NSLocalizedString(@"send.failed_message", nil);
        alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"send.failed_title", nil)
                                           message:message
                                          delegate:nil
                                 cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                 otherButtonTitles:nil];
    }
    [alert show];
    [alert release];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_tableView release];
    [_emptyLabel release];
    [_addButton release];
    [_pendingItems release];
    [_mediaPopover release];
    [_typeSheet release];
    [super dealloc];
}

@end
