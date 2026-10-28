#import "MediaPickerViewController.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@protocol MediaSelectionCircle <NSObject>
- (void)setChecked:(BOOL)checked;
@end

static MediaPickerViewController *gActiveMediaPicker = nil;
static id gActiveGroup = nil;
static id gActiveFilter = nil;

static NSInteger MediaColumns(CGFloat width) {
    return width > 500.0f ? 8 : 4;
}

static CGFloat MediaThumbSize(CGFloat width, NSInteger columns) {
    CGFloat gap = 8.0f;
    return floorf((width - (columns + 1) * gap) / columns);
}

@interface MediaVideoOverlayView : UIView {
    UILabel *_durationLabel;
    UIImageView *_iconView;
}
- (void)setDuration:(double)seconds;
@end

@implementation MediaVideoOverlayView

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;

        _durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _durationLabel.backgroundColor = [UIColor clearColor];
        _durationLabel.font = [UIFont boldSystemFontOfSize:13];
        _durationLabel.textColor = [UIColor whiteColor];
        _durationLabel.textAlignment = UITextAlignmentRight;
        [self addSubview:_durationLabel];

        _iconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"MediaVideoIcon.png"]];
        _iconView.backgroundColor = [UIColor clearColor];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];
    }
    return self;
}

- (void)setDuration:(double)seconds {
    NSInteger total = (NSInteger)(seconds + 0.5);
    NSInteger hours;
    NSInteger minutes;
    NSInteger secs;

    if (total < 0) total = 0;
    hours = total / 3600;
    minutes = (total % 3600) / 60;
    secs = total % 60;

    if (hours > 0) {
        _durationLabel.text = [NSString stringWithFormat:@"%d:%02d:%02d",
                               (int)hours, (int)minutes, (int)secs];
    } else {
        _durationLabel.text = [NSString stringWithFormat:@"%d:%02d",
                               (int)minutes, (int)secs];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat barHeight = self.bounds.size.height * 0.30f;
    if (barHeight > 18.0f) barHeight = 18.0f;
    if (barHeight < 12.0f) barHeight = 12.0f;
    _durationLabel.frame = CGRectMake(self.bounds.size.width - 66.0f,
                                      self.bounds.size.height - barHeight,
                                      60.0f, barHeight);
    _iconView.frame = CGRectMake(5.0f,
                                 self.bounds.size.height - barHeight + (barHeight - 10.0f) / 2.0f,
                                 16.0f, 10.0f);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat barHeight = self.bounds.size.height * 0.30f;
    CGFloat barY;
    CGFloat iconW = 12.0f;
    CGFloat iconH = 9.0f;
    CGFloat iconX = 5.0f;
    CGFloat iconY;

    if (barHeight > 18.0f) barHeight = 18.0f;
    if (barHeight < 12.0f) barHeight = 12.0f;
    barY = self.bounds.size.height - barHeight;
    iconY = barY + (barHeight - iconH) / 2.0f;

    CGContextSetFillColorWithColor(context,
                                   [UIColor colorWithWhite:0.0f alpha:0.46f].CGColor);
    CGContextFillRect(context, CGRectMake(0, barY, self.bounds.size.width, barHeight));

}

- (void)dealloc {
    [_durationLabel release];
    [_iconView release];
    [super dealloc];
}

@end

@interface MediaThumbCell : UITableViewCell {
    UIButton *_buttons[8];
    id _checkViews[8];
    id _videoOverlays[8];
}
- (UIButton *)buttonAtIndex:(NSInteger)index;
- (id)checkViewAtIndex:(NSInteger)index;
- (id)videoOverlayAtIndex:(NSInteger)index;
@end

@implementation MediaThumbCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        NSInteger i;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        for (i = 0; i < 8; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.backgroundColor = [UIColor colorWithWhite:0.88f alpha:1.0f];
            button.clipsToBounds = YES;
            button.layer.borderColor = [UIColor colorWithRed:0.12f green:0.42f blue:0.80f alpha:1.0f].CGColor;
            button.adjustsImageWhenHighlighted = NO;
            [self.contentView addSubview:button];
            _buttons[i] = [button retain];

            {
                MediaVideoOverlayView *overlay = [[MediaVideoOverlayView alloc] initWithFrame:CGRectZero];
                overlay.hidden = YES;
                [self.contentView addSubview:overlay];
                _videoOverlays[i] = overlay;
            }

            {
                Class circleClass = NSClassFromString(@"SelectionCircleView");
                if (circleClass != nil) {
                    UIView *circle = [[circleClass alloc] initWithFrame:CGRectZero];
                    circle.hidden = YES;
                    circle.userInteractionEnabled = NO;
                    [self.contentView addSubview:circle];
                    _checkViews[i] = circle;
                }
            }
        }
    }
    return self;
}

- (UIButton *)buttonAtIndex:(NSInteger)index {
    if (index < 0 || index >= 8) return nil;
    return _buttons[index];
}

- (id)checkViewAtIndex:(NSInteger)index {
    if (index < 0 || index >= 8) return nil;
    return _checkViews[index];
}

- (id)videoOverlayAtIndex:(NSInteger)index {
    if (index < 0 || index >= 8) return nil;
    return _videoOverlays[index];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    NSInteger columns = MediaColumns(width);
    CGFloat gap = 8.0f;
    CGFloat thumb = MediaThumbSize(width, columns);
    NSInteger i;

    for (i = 0; i < 8; i++) {
        if (i < columns) {
            _buttons[i].hidden = NO;
            _buttons[i].frame = CGRectMake(gap + i * (thumb + gap), gap, thumb, thumb);
            _buttons[i].imageView.contentMode = UIViewContentModeScaleAspectFill;
            if (_videoOverlays[i] != nil) {
                [(UIView *)_videoOverlays[i] setFrame:_buttons[i].frame];
            }
            if (_checkViews[i] != nil) {
                [(UIView *)_checkViews[i] setFrame:CGRectMake(CGRectGetMaxX(_buttons[i].frame) - 36.0f,
                                                              CGRectGetMaxY(_buttons[i].frame) - 36.0f,
                                                              36.0f, 36.0f)];
                [self.contentView bringSubviewToFront:(UIView *)_checkViews[i]];
            }
        } else {
            _buttons[i].hidden = YES;
            if (_videoOverlays[i] != nil) [(UIView *)_videoOverlays[i] setHidden:YES];
            if (_checkViews[i] != nil) [(UIView *)_checkViews[i] setHidden:YES];
        }
    }
}

- (void)dealloc {
    NSInteger i;
    for (i = 0; i < 8; i++) {
        [_buttons[i] release];
        [(id)_videoOverlays[i] release];
        [(id)_checkViews[i] release];
    }
    [super dealloc];
}

@end

@implementation MediaPickerViewController

@synthesize delegate = _delegate;

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor whiteColor];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _tableView = [[UITableView alloc] initWithFrame:view.bounds style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.backgroundColor = [UIColor whiteColor];
    _tableView.delaysContentTouches = NO;
    _tableView.canCancelContentTouches = YES;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:_tableView];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 120, frame.size.width - 40, 60)];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.font = [UIFont boldSystemFontOfSize:13];
    _emptyLabel.textAlignment = UITextAlignmentCenter;
    _emptyLabel.textColor = [UIColor grayColor];
    _emptyLabel.numberOfLines = 2;
    _emptyLabel.text = NSLocalizedString(@"media.no_photos", nil);
    _emptyLabel.hidden = YES;
    [view addSubview:_emptyLabel];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.frame = CGRectMake((frame.size.width - 37) / 2, (frame.size.height - 37) / 2, 37, 37);
    _spinner.hidesWhenStopped = YES;
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [view addSubview:_spinner];

    self.view = view;
    [view release];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"media.picker_title", nil);

    _assets = [[NSMutableArray alloc] init];
    _selectedIndexes = [[NSMutableSet alloc] init];
    _previewIndex = -1;

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                           target:self
                                                                           action:@selector(cancelTapped:)];
    self.navigationItem.leftBarButtonItem = cancel;
    [cancel release];

    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"common.done", nil)
                                                             style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(doneTapped:)];
    self.navigationItem.rightBarButtonItem = done;
    done.enabled = NO;
    [done release];

    [self loadAssets];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _emptyLabel.frame = CGRectMake(20, self.view.bounds.size.height * 0.4f,
                                   self.view.bounds.size.width - 40, 60);
    _spinner.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if ([[[UIDevice currentDevice] model] rangeOfString:@"iPad"].location != NSNotFound) {
        return YES;
    }
    return orientation == UIInterfaceOrientationPortrait;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation
                                         duration:(NSTimeInterval)duration {
    _emptyLabel.frame = CGRectMake(20, self.view.bounds.size.height * 0.4f,
                                   self.view.bounds.size.width - 40, 60);
    _spinner.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    [_tableView reloadData];
}

- (void)loadAssets {
    ALAssetsLibrary *library;

    _loading = YES;

    [_loadingAssets release];
    _loadingAssets = [[NSMutableArray alloc] init];
    [_spinner startAnimating];

    library = [[ALAssetsLibrary alloc] init];
    if (library == nil) {
        [self finishLoading];
        return;
    }

    _library = library;
    if (gActiveMediaPicker != self) {
        [gActiveMediaPicker release];
        gActiveMediaPicker = [self retain];
    }

    [library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos
                           usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        if (group == nil) {
            [gActiveMediaPicker performSelectorOnMainThread:@selector(finishLoading)
                                                 withObject:nil
                                              waitUntilDone:NO];
            return;
        }

        {
            ALAssetsFilter *filter = [ALAssetsFilter allAssets];
            [group setAssetsFilter:filter];

            if (gActiveGroup != group) {
                [gActiveGroup release];
                gActiveGroup = [group retain];
            }
            if (gActiveFilter != filter) {
                [gActiveFilter release];
                gActiveFilter = [filter retain];
            }
        }

        [group enumerateAssetsUsingBlock:^(ALAsset *asset, NSUInteger index, BOOL *stop2) {
            if (asset != nil) {
                [gActiveMediaPicker addLoadingAsset:asset];
            }
        }];
    }
                          failureBlock:^(NSError *error) {
        [gActiveMediaPicker performSelectorOnMainThread:@selector(finishLoading)
                                             withObject:nil
                                          waitUntilDone:NO];
    }];
}

- (void)addLoadingAsset:(id)asset {
    if (asset != nil) [_loadingAssets addObject:asset];
}

- (void)finishLoading {
    if (!_loading) return;
    _loading = NO;

    [_spinner stopAnimating];
    [_assets release];
    _assets = [_loadingAssets retain];
    [_loadingAssets release];
    _loadingAssets = nil;
    [_library release];
    _library = nil;
    [gActiveGroup release];
    gActiveGroup = nil;
    [gActiveFilter release];
    gActiveFilter = nil;

    _emptyLabel.hidden = ([_assets count] > 0);
    [_tableView reloadData];
    [self updateDoneButton];

    if (gActiveMediaPicker == self) {
        gActiveMediaPicker = nil;
        [self release];
    }
}

- (void)updateDoneButton {
    NSUInteger selected = [_selectedIndexes count];
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"media.done_count", nil),
                       (int)selected];
    self.navigationItem.rightBarButtonItem.title = title;
    self.navigationItem.rightBarButtonItem.enabled = (selected > 0);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger columns = MediaColumns(tableView.bounds.size.width);
    return (NSInteger)(([_assets count] + columns - 1) / columns);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = tableView.bounds.size.width;
    NSInteger columns = MediaColumns(width);
    return MediaThumbSize(width, columns) + 16.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MediaThumbCell";
    MediaThumbCell *cell = (MediaThumbCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    NSInteger columns;
    NSInteger i;

    if (cell == nil) {
        cell = [[[MediaThumbCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier] autorelease];
    }
    cell.backgroundColor = [UIColor whiteColor];
    cell.contentView.backgroundColor = [UIColor whiteColor];

    columns = MediaColumns(tableView.bounds.size.width);
    for (i = 0; i < 8; i++) {
        UIButton *button = [cell buttonAtIndex:i];
        id check = [cell checkViewAtIndex:i];
        NSInteger assetIndex = indexPath.row * columns + i;

        [button removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        button.backgroundColor = [UIColor clearColor];
        button.layer.borderWidth = 0.0f;

        if (i < columns && assetIndex < (NSInteger)[_assets count]) {
            ALAsset *asset = [_assets objectAtIndex:assetIndex];
            CGImageRef thumbnail = [asset thumbnail];
            UIImage *image = thumbnail != NULL ? [UIImage imageWithCGImage:thumbnail] : nil;
            BOOL selected = [_selectedIndexes containsObject:
                             [NSNumber numberWithInteger:assetIndex]];

            button.hidden = NO;
            button.tag = assetIndex;
            [button setBackgroundImage:image forState:UIControlStateNormal];
            [button addTarget:self
                       action:@selector(thumbTouchDown:)
             forControlEvents:UIControlEventTouchDown];
            [button addTarget:self
                       action:@selector(thumbTouchUp:)
             forControlEvents:UIControlEventTouchUpInside];
            [button addTarget:self
                       action:@selector(thumbTouchCancel:)
             forControlEvents:UIControlEventTouchCancel | UIControlEventTouchDragExit];
            [button addTarget:self
                       action:@selector(thumbTouchEnter:)
             forControlEvents:UIControlEventTouchDragEnter];
            {
                id overlay = [cell videoOverlayAtIndex:i];
                BOOL isVideo = [[asset valueForProperty:ALAssetPropertyType]
                                isEqualToString:ALAssetTypeVideo];
                if (overlay != nil) {
                    [overlay setHidden:!isVideo];
                    if (isVideo) {
                        double duration = [[asset valueForProperty:ALAssetPropertyDuration] doubleValue];
                        [(MediaVideoOverlayView *)overlay setDuration:duration];
                    }
                }
            }
            if (check != nil) {
                [check setHidden:!selected];
                [(id<MediaSelectionCircle>)check setChecked:selected];
            }
        } else {
            button.hidden = YES;
            button.tag = -1;
            [button setBackgroundImage:nil forState:UIControlStateNormal];
            {
                id overlay = [cell videoOverlayAtIndex:i];
                if (overlay != nil) [overlay setHidden:YES];
            }
            if (check != nil) [check setHidden:YES];
        }
    }
    return cell;
}

- (void)setCheckForIndex:(NSInteger)index selected:(BOOL)selected {
    NSInteger columns = MediaColumns(_tableView.bounds.size.width);
    NSInteger row = index / columns;
    NSInteger column = index % columns;
    NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
    MediaThumbCell *cell = (MediaThumbCell *)[_tableView cellForRowAtIndexPath:path];
    id check = [cell checkViewAtIndex:column];

    if (check != nil) {
        [(UIView *)check setHidden:!selected];
        [(id<MediaSelectionCircle>)check setChecked:selected];
    }
}

- (void)thumbTouchDown:(UIButton *)sender {
    NSNumber *key = [NSNumber numberWithInteger:sender.tag];

    _previewIndex = sender.tag;
    _previewWasSelected = [_selectedIndexes containsObject:key];
    [self setCheckForIndex:_previewIndex selected:!_previewWasSelected];
}

- (void)thumbTouchUp:(UIButton *)sender {
    NSNumber *key = [NSNumber numberWithInteger:sender.tag];

    if (sender.tag == _previewIndex) {
        if (_previewWasSelected) {
            [_selectedIndexes removeObject:key];
        } else {
            [_selectedIndexes addObject:key];
        }
        [self setCheckForIndex:sender.tag selected:!_previewWasSelected];
        _previewIndex = -1;
        [self updateDoneButton];
    }
}

- (void)thumbTouchCancel:(UIButton *)sender {
    if (sender.tag == _previewIndex) {
        [self setCheckForIndex:_previewIndex selected:_previewWasSelected];
        _previewIndex = -1;
    }
}

- (void)thumbTouchEnter:(UIButton *)sender {
    if (sender.tag == _previewIndex) {
        [self setCheckForIndex:_previewIndex selected:!_previewWasSelected];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (_previewIndex >= 0) {
        [self setCheckForIndex:_previewIndex selected:_previewWasSelected];
        _previewIndex = -1;
    }
}

- (void)cancelTapped:(id)sender {
    if ([_delegate respondsToSelector:@selector(mediaPickerDidCancel:)]) {
        [_delegate mediaPickerDidCancel:self];
    } else {
        [self dismissModalViewControllerAnimated:YES];
    }
}

- (void)showExportHUD {
    UIView *container;
    UIView *box;
    UIActivityIndicatorView *spinner;
    CGRect bounds;

    if (_exportHUD != nil) return;
    container = self.navigationController != nil ? self.navigationController.view : self.view;
    bounds = container.bounds;

    _exportHUD = [[UIView alloc] initWithFrame:bounds];
    _exportHUD.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.28f];
    _exportHUD.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _exportHUD.userInteractionEnabled = YES;

    box = [[UIView alloc] initWithFrame:CGRectMake((bounds.size.width - 86.0f) / 2.0f,
                                                   (bounds.size.height - 86.0f) / 2.0f,
                                                   86.0f, 86.0f)];
    box.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.78f];
    box.layer.cornerRadius = 12.0f;
    box.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                           UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    box.userInteractionEnabled = NO;
    [_exportHUD addSubview:box];

    spinner = [[UIActivityIndicatorView alloc]
               initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spinner.frame = CGRectMake((86.0f - 37.0f) / 2.0f, (86.0f - 37.0f) / 2.0f, 37.0f, 37.0f);
    spinner.hidesWhenStopped = NO;
    [spinner startAnimating];
    [box addSubview:spinner];

    [spinner release];
    [box release];
    [container addSubview:_exportHUD];
}

- (void)hideExportHUD {
    [_exportHUD removeFromSuperview];
    [_exportHUD release];
    _exportHUD = nil;
}

- (void)doneTapped:(id)sender {
    if (_exporting) return;
    _exporting = YES;

    self.navigationItem.leftBarButtonItem.enabled = NO;
    _tableView.userInteractionEnabled = NO;
    [self showExportHUD];

    [self performSelectorInBackground:@selector(exportSelectedItems)
                           withObject:nil];
}

- (NSArray *)selectedItems {
    NSMutableArray *items = [NSMutableArray array];
    NSArray *indexes = [[_selectedIndexes allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSInteger i;

    for (i = 0; i < (NSInteger)[indexes count]; i++) {
        NSInteger index = [[indexes objectAtIndex:i] integerValue];
        ALAsset *asset;
        NSString *assetType;

        if (index < 0 || index >= (NSInteger)[_assets count]) continue;
        asset = [_assets objectAtIndex:index];
        assetType = [asset valueForProperty:ALAssetPropertyType];

        if ([assetType isEqualToString:ALAssetTypeVideo]) {
            ALAssetRepresentation *representation = [asset defaultRepresentation];
            long long size = [representation size];
            NSString *uti = [[representation UTI] lowercaseString];
            NSString *extension = @"mov";
            NSString *mime = @"video/quicktime";
            NSString *name;
            NSString *path;
            NSFileHandle *handle;
            uint8_t *buffer;
            long long offset = 0;

            if ([uti rangeOfString:@"mpeg-4"].location != NSNotFound ||
                [uti rangeOfString:@"mp4"].location != NSNotFound) {
                extension = @"mp4";
                mime = @"video/mp4";
            } else if ([uti rangeOfString:@"m4v"].location != NSNotFound) {
                extension = @"m4v";
                mime = @"video/x-m4v";
            }

            name = [NSString stringWithFormat:@"media-%u-%u.%@",
                    (unsigned)[[NSDate date] timeIntervalSince1970],
                    (unsigned)arc4random(), extension];
            path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];

            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
            handle = [NSFileHandle fileHandleForWritingAtPath:path];
            buffer = (uint8_t *)malloc(256 * 1024);

            if (handle != nil && buffer != NULL) {
                while (offset < size) {
                    NSUInteger length = (NSUInteger)MIN((long long)(256 * 1024), size - offset);
                    NSError *error = nil;
                    NSUInteger read = [representation getBytes:buffer
                                                    fromOffset:offset
                                                        length:length
                                                         error:&error];
                    if (read == 0) break;
                    [handle writeData:[NSData dataWithBytes:buffer length:read]];
                    offset += read;
                }
                [handle closeFile];
            }
            if (buffer != NULL) free(buffer);

            if (offset > 0) {
                [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    @"video", @"kind",
                    path, @"path",
                    name, @"name",
                    mime, @"type",
                    [NSNumber numberWithLongLong:size], @"size", nil]];
            } else {
                [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            }
        } else {
            ALAssetRepresentation *representation = [asset defaultRepresentation];
            CGImageRef imageRef = [representation fullScreenImage];
            if (imageRef == NULL) imageRef = [representation fullResolutionImage];
            if (imageRef != NULL) {
                UIImage *image = [UIImage imageWithCGImage:imageRef
                                                    scale:1.0f
                                              orientation:(UIImageOrientation)[representation orientation]];
                if (image != nil) {
                    [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                        @"image", @"kind",
                        image, @"image", nil]];
                }
            }
        }
    }
    return items;
}

- (void)exportSelectedItems {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSArray *items = [[self selectedItems] retain];

    [self performSelectorOnMainThread:@selector(finishExportWithItems:)
                           withObject:items
                        waitUntilDone:NO];
    [items release];
    [pool release];
}

- (void)finishExportWithItems:(NSArray *)items {
    _exporting = NO;
    [self hideExportHUD];
    self.navigationItem.leftBarButtonItem.enabled = YES;
    _tableView.userInteractionEnabled = YES;

    if ([_delegate respondsToSelector:@selector(mediaPicker:didFinishWithItems:)]) {
        [_delegate mediaPicker:self didFinishWithItems:items];
    } else {
        [self dismissModalViewControllerAnimated:YES];
    }
}

- (void)dealloc {
    if (gActiveMediaPicker == self) gActiveMediaPicker = nil;
    [gActiveGroup release];
    gActiveGroup = nil;
    [gActiveFilter release];
    gActiveFilter = nil;
    [_tableView release];
    [_assets release];
    [_loadingAssets release];
    [_selectedIndexes release];
    [_spinner release];
    [_exportHUD release];
    [_emptyLabel release];
    [_library release];
    [super dealloc];
}

@end

