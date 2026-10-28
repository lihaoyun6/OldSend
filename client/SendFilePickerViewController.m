#import "SendFilePickerViewController.h"
#import "OSPlatform.h"
#import "SelectionCircleView.h"
#import "FileTypeIcon.h"
#include <math.h>

#define OS_FILES_START_PATH @"/var/mobile"

static NSComparisonResult OSCompareEntryNames(id first, id second, void *context) {
    NSString *firstName = [first objectForKey:@"name"];
    NSString *secondName = [second objectForKey:@"name"];
    return [firstName localizedCaseInsensitiveCompare:secondName];
}

@interface SendFileCell : UITableViewCell {
    SelectionCircleView *_checkView;
    UIImageView *_iconView;
    UILabel *_nameLabel;
    UILabel *_detailLabel;
}
- (void)configureName:(NSString *)name detail:(NSString *)detail selected:(BOOL)selected;
@end

@implementation SendFileCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _checkView = [[SelectionCircleView alloc] init];
        [self.contentView addSubview:_checkView];

        _iconView = [[UIImageView alloc] init];
        _iconView.backgroundColor = [UIColor clearColor];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_iconView];

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
    }
    return self;
}

- (void)configureName:(NSString *)name detail:(NSString *)detail selected:(BOOL)selected {
    _nameLabel.text = name;
    _detailLabel.text = detail;
    _iconView.image = [UIImage imageNamed:OSFileTypeIconName(name)];
    [_checkView setChecked:selected];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    CGFloat top = floorf((bounds.size.height - 40.0f) / 2.0f);

    _checkView.frame = CGRectMake(4, (bounds.size.height - 36) / 2, 36, 36);
    _iconView.frame = CGRectMake(48.0f,
                                 floorf((bounds.size.height - 32.0f) / 2.0f),
                                 32.0f, 32.0f);
    _nameLabel.frame = CGRectMake(90, top, bounds.size.width - 100, 22);
    _detailLabel.frame = CGRectMake(90, top + 22, bounds.size.width - 100, 18);
}

- (void)dealloc {
    [_checkView release];
    [_iconView release];
    [_nameLabel release];
    [_detailLabel release];
    [super dealloc];
}

@end

@interface OSArrowButton : UIButton {
    BOOL _pointsLeft;
}
- (id)initWithFrame:(CGRect)frame pointsLeft:(BOOL)pointsLeft;
@end

@implementation OSArrowButton

- (id)initWithFrame:(CGRect)frame pointsLeft:(BOOL)pointsLeft {
    if ((self = [super initWithFrame:frame])) {
        _pointsLeft = pointsLeft;
        self.backgroundColor = [UIColor clearColor];
        self.showsTouchWhenHighlighted = YES;
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    CGFloat cx = CGRectGetMidX(bounds);
    CGFloat cy = CGRectGetMidY(bounds);
    CGFloat width = 11.0f;
    CGFloat height = 16.0f;

    CGContextSetFillColorWithColor(context,
        [UIColor colorWithWhite:1.0f alpha:(self.enabled ? 0.95f : 0.35f)].CGColor);
    if (_pointsLeft) {
        CGContextMoveToPoint(context, cx + width / 2.0f, cy - height / 2.0f);
        CGContextAddLineToPoint(context, cx - width / 2.0f, cy);
        CGContextAddLineToPoint(context, cx + width / 2.0f, cy + height / 2.0f);
    } else {
        CGContextMoveToPoint(context, cx - width / 2.0f, cy - height / 2.0f);
        CGContextAddLineToPoint(context, cx + width / 2.0f, cy);
        CGContextAddLineToPoint(context, cx - width / 2.0f, cy + height / 2.0f);
    }
    CGContextClosePath(context);
    CGContextFillPath(context);
}

@end

@implementation SendFilePickerViewController

@synthesize delegate = _delegate;

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor whiteColor];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _tableView = [[UITableView alloc] initWithFrame:view.bounds style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 54;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:_tableView];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 110, frame.size.width - 40, 120)];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.font = OSSmallFont(13);
    _emptyLabel.textAlignment = UITextAlignmentCenter;
    _emptyLabel.textColor = [UIColor grayColor];
    _emptyLabel.numberOfLines = 3;
    _emptyLabel.text = NSLocalizedString(@"send.files_empty", nil);
    [view addSubview:_emptyLabel];

    _pathLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, frame.size.height - 22,
                                                           frame.size.width - 20, 20)];
    _pathLabel.backgroundColor = [UIColor clearColor];
    _pathLabel.font = OSSmallFont(OSIsPad() ? 13.0f : 11.0f);
    _pathLabel.textAlignment = UITextAlignmentCenter;
    _pathLabel.textColor = [UIColor colorWithWhite:0.55f alpha:1.0f];
    _pathLabel.lineBreakMode = UILineBreakModeMiddleTruncation;
    _pathLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [view addSubview:_pathLabel];

    _toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, frame.size.height - 44,
                                                           frame.size.width, 44)];
    _toolbar.barStyle = UIBarStyleDefault;
    _toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    _backButton = [[OSArrowButton alloc] initWithFrame:CGRectMake(0, 0, 44, 32)
                                           pointsLeft:YES];
    [_backButton addTarget:self action:@selector(goUp) forControlEvents:UIControlEventTouchUpInside];
    _backItem = [[UIBarButtonItem alloc] initWithCustomView:_backButton];

    _forwardButton = [[OSArrowButton alloc] initWithFrame:CGRectMake(0, 0, 44, 32)
                                               pointsLeft:NO];
    [_forwardButton addTarget:self action:@selector(goForward) forControlEvents:UIControlEventTouchUpInside];
    _forwardItem = [[UIBarButtonItem alloc] initWithCustomView:_forwardButton];
    {
        UIBarButtonItem *flexible = [[UIBarButtonItem alloc]
                                     initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                          target:nil
                                                          action:nil];
        _toolbar.items = [NSArray arrayWithObjects:_backItem, flexible, _forwardItem, nil];
        [flexible release];
    }
    [view addSubview:_toolbar];

    self.view = view;
    [view release];

    [self layoutContent];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"send.files_title", nil);
    _selectedPaths = [[NSMutableSet alloc] init];
    _forwardPaths = [[NSMutableArray alloc] init];
    if (_currentPath == nil) {
        _currentPath = [OS_FILES_START_PATH copy];
    }

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

    [self reloadFiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self layoutContent];
    [self reloadFiles];
}

- (void)layoutContent {
    CGRect bounds = self.view.bounds;
    CGFloat pathHeight = 22.0f;
    CGFloat toolbarHeight = 44.0f;

    _tableView.frame = CGRectMake(0, 0, bounds.size.width,
                                  bounds.size.height - pathHeight - toolbarHeight);
    _pathLabel.frame = CGRectMake(10, bounds.size.height - pathHeight - toolbarHeight,
                                  bounds.size.width - 20, pathHeight);
    _toolbar.frame = CGRectMake(0, bounds.size.height - toolbarHeight,
                                bounds.size.width, toolbarHeight);
    _emptyLabel.frame = CGRectMake(20, floorf((bounds.size.height - 120.0f) / 2.0f),
                                   bounds.size.width - 40, 120);
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

- (NSString *)parentPath {
    return [_currentPath stringByDeletingLastPathComponent];
}

- (void)reloadFiles {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableArray *directories = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];
    NSArray *names;
    NSError *error = nil;

    names = [manager contentsOfDirectoryAtPath:_currentPath error:&error];
    for (NSString *name in names) {
        NSString *path;
        NSDictionary *attributes;
        BOOL isDirectory = NO;

        if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) continue;
        path = [_currentPath stringByAppendingPathComponent:name];
        if (![manager fileExistsAtPath:path isDirectory:&isDirectory]) continue;

        attributes = [manager attributesOfItemAtPath:path error:NULL];
        {
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            [entry setObject:name forKey:@"name"];
            [entry setObject:path forKey:@"path"];
            [entry setObject:[NSNumber numberWithBool:isDirectory] forKey:@"isDirectory"];
            [entry setObject:[attributes objectForKey:NSFileSize] ?: [NSNumber numberWithLongLong:0]
                      forKey:@"size"];
            [entry setObject:[attributes objectForKey:NSFileModificationDate] ?: [NSDate date]
                      forKey:@"date"];
            if (isDirectory) {
                [directories addObject:entry];
            } else {
                [files addObject:entry];
            }
        }
    }

    directories = [[directories sortedArrayUsingFunction:OSCompareEntryNames
                                                context:NULL] mutableCopy];
    files = [[files sortedArrayUsingFunction:OSCompareEntryNames
                                    context:NULL] mutableCopy];

    [_entries release];
    _entries = [[directories arrayByAddingObjectsFromArray:files] copy];
    [directories release];
    [files release];

    _pathLabel.text = _currentPath;
    _emptyLabel.text = (names == nil && error != nil)
                       ? NSLocalizedString(@"send.files_unreadable", nil)
                       : NSLocalizedString(@"send.files_empty", nil);
    _emptyLabel.hidden = ([_entries count] > 0);
    _tableView.separatorStyle = [_entries count] > 0
                                ? UITableViewCellSeparatorStyleSingleLine
                                : UITableViewCellSeparatorStyleNone;
    _backButton.enabled = ![_currentPath isEqualToString:@"/"];
    _forwardButton.enabled = ([_forwardPaths count] > 0);
    [_tableView reloadData];
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

- (NSString *)formatDate:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    if (formatter == nil) {
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateStyle:NSDateFormatterMediumStyle];
        [formatter setTimeStyle:NSDateFormatterShortStyle];
    }
    return [formatter stringFromDate:date];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[_entries count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    {
        NSDictionary *entry = [_entries objectAtIndex:indexPath.row];
        if ([[entry objectForKey:@"isDirectory"] boolValue]) {
            static NSString *directoryIdentifier = @"DirectoryCell";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:directoryIdentifier];
            if (cell == nil) {
                cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                               reuseIdentifier:directoryIdentifier] autorelease];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            cell.textLabel.text = [entry objectForKey:@"name"];
            cell.imageView.image = [UIImage imageNamed:@"folder.png"];
            return cell;
        }
    }

    {
        static NSString *identifier = @"FileCell";
        SendFileCell *cell = (SendFileCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
        NSDictionary *entry = [_entries objectAtIndex:indexPath.row];
        long long size = [[entry objectForKey:@"size"] longLongValue];

        if (cell == nil) {
            cell = [[[SendFileCell alloc] initWithStyle:UITableViewCellStyleDefault
                                        reuseIdentifier:identifier] autorelease];
        }
        [cell configureName:[entry objectForKey:@"name"]
                     detail:[NSString stringWithFormat:@"%@ · %@",
                             [self formatBytes:size],
                             [self formatDate:[entry objectForKey:@"date"]]]
                   selected:[_selectedPaths containsObject:[entry objectForKey:@"path"]]];
        return cell;
    }
}

- (void)updateDoneButton {
    self.navigationItem.rightBarButtonItem.enabled = ([_selectedPaths count] > 0);
}

- (void)goUp {
    if ([_currentPath isEqualToString:@"/"]) return;
    [_forwardPaths addObject:_currentPath];
    [_currentPath release];
    _currentPath = [[self parentPath] copy];
    [self reloadFiles];
    [_tableView setContentOffset:CGPointZero animated:NO];
}

- (void)goForward {
    NSString *path;

    if ([_forwardPaths count] == 0) return;
    path = [[_forwardPaths lastObject] retain];
    [_forwardPaths removeLastObject];
    [_currentPath release];
    _currentPath = [path copy];
    [path release];
    [self reloadFiles];
    [_tableView setContentOffset:CGPointZero animated:NO];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    {
        NSDictionary *entry = [_entries objectAtIndex:indexPath.row];
        if ([[entry objectForKey:@"isDirectory"] boolValue]) {
            [_forwardPaths removeAllObjects];
            [_currentPath release];
            _currentPath = [[entry objectForKey:@"path"] copy];
            [self reloadFiles];
            [tableView setContentOffset:CGPointZero animated:NO];
            return;
        }

        {
            NSString *path = [entry objectForKey:@"path"];
            if ([_selectedPaths containsObject:path]) {
                [_selectedPaths removeObject:path];
            } else {
                [_selectedPaths addObject:path];
            }
            [tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                             withRowAnimation:UITableViewRowAnimationNone];
            [self updateDoneButton];
        }
    }
}

- (void)doneTapped:(id)sender {
    NSFileManager *manager = [NSFileManager defaultManager];

    for (NSString *path in _selectedPaths) {
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        if (attributes == nil) continue;
        if ([_delegate respondsToSelector:@selector(sendFilePicker:didSelectFile:name:size:)]) {
            [_delegate sendFilePicker:self
                        didSelectFile:path
                                 name:[path lastPathComponent]
                                 size:[[attributes objectForKey:NSFileSize] longLongValue]];
        }
    }
    [self dismissModalViewControllerAnimated:YES];
}

- (void)cancelTapped:(id)sender {
    if ([_delegate respondsToSelector:@selector(sendFilePickerDidCancel:)]) {
        [_delegate sendFilePickerDidCancel:self];
    }
    [self dismissModalViewControllerAnimated:YES];
}

- (void)dealloc {
    [_tableView release];
    [_emptyLabel release];
    [_pathLabel release];
    [_toolbar release];
    [_backItem release];
    [_forwardItem release];
    [_backButton release];
    [_forwardButton release];
    [_entries release];
    [_currentPath release];
    [_selectedPaths release];
    [_forwardPaths release];
    [super dealloc];
}

@end
