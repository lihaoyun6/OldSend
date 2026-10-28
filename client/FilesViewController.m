#import "FilesViewController.h"
#import "OSPlatform.h"
#import "SelectionCircleView.h"
#import "FileTypeIcon.h"
#import "OSServer.h"
#include <math.h>

#define OS_RECEIVED_PATH @"/var/mobile/Library/OldSend/Received"

@interface FileCell : UITableViewCell {
    SelectionCircleView *_checkView;
    UIImageView *_iconView;
    UILabel *_nameLabel;
    UILabel *_detailLabel;
}
- (void)configureName:(NSString *)name detail:(NSString *)detail editing:(BOOL)editing selected:(BOOL)selected;
@end

@implementation FileCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _checkView = [[SelectionCircleView alloc] init];
        _checkView.hidden = YES;
        _checkView.contentMode = UIViewContentModeRedraw;
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

- (void)configureName:(NSString *)name detail:(NSString *)detail editing:(BOOL)editing selected:(BOOL)selected {
    _nameLabel.text = name;
    _detailLabel.text = detail;
    _iconView.image = [UIImage imageNamed:OSFileTypeIconName(name)];
    _checkView.hidden = !editing;
    [_checkView setChecked:selected];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    BOOL editing = !_checkView.hidden;
    CGFloat left = editing ? 90.0f : 52.0f;
    CGFloat top = floorf((bounds.size.height - 40.0f) / 2.0f);

    _checkView.frame = CGRectMake(4, (bounds.size.height - 36) / 2, 36, 36);
    _iconView.frame = CGRectMake(editing ? 48.0f : 10.0f,
                                 floorf((bounds.size.height - 32.0f) / 2.0f),
                                 32.0f, 32.0f);
    _nameLabel.frame = CGRectMake(left, top, bounds.size.width - left - 10, 22);
    _detailLabel.frame = CGRectMake(left, top + 22, bounds.size.width - left - 10, 18);
}

- (void)dealloc {
    [_checkView release];
    [_iconView release];
    [_nameLabel release];
    [_detailLabel release];
    [super dealloc];
}

@end

@implementation FilesViewController

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor whiteColor];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _tableView = [[UITableView alloc] initWithFrame:view.bounds style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = OSIsPad() ? 68.0f : 54.0f;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:_tableView];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 150, frame.size.width - 40, 60)];
    _emptyLabel.backgroundColor = [UIColor whiteColor];
    _emptyLabel.font = OSSmallFont(13);
    _emptyLabel.textAlignment = UITextAlignmentCenter;
    _emptyLabel.textColor = [UIColor grayColor];
    _emptyLabel.numberOfLines = 2;
    _emptyLabel.text = NSLocalizedString(@"files.empty", nil);
    [view addSubview:_emptyLabel];

    _toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, frame.size.height - 44,
                                                          frame.size.width, 44)];
    _toolbar.barStyle = UIBarStyleDefault;
    _toolbar.hidden = YES;
    _toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

    _selectAllControl = [[UISegmentedControl alloc] initWithItems:
                         [NSArray arrayWithObject:NSLocalizedString(@"files.select_all", nil)]];
    _selectAllControl.frame = CGRectMake(0, 0, 76, 30);
    _selectAllControl.segmentedControlStyle = UISegmentedControlStyleBar;
    _selectAllControl.momentary = YES;
    [_selectAllControl addTarget:self action:@selector(selectAllTapped)
                forControlEvents:UIControlEventValueChanged];
    _selectAllItem = [[UIBarButtonItem alloc] initWithCustomView:_selectAllControl];

    _deleteControl = [[UISegmentedControl alloc] initWithItems:
                      [NSArray arrayWithObject:NSLocalizedString(@"files.delete", nil)]];
    _deleteControl.frame = CGRectMake(0, 0, 76, 30);
    _deleteControl.segmentedControlStyle = UISegmentedControlStyleBar;
    _deleteControl.tintColor = [UIColor colorWithRed:0.82f green:0.14f blue:0.14f alpha:1.0f];
    _deleteControl.momentary = YES;
    [_deleteControl addTarget:self action:@selector(deleteSelected)
             forControlEvents:UIControlEventValueChanged];
    _deleteControl.enabled = NO;

    _deleteItem = [[UIBarButtonItem alloc] initWithCustomView:_deleteControl];

    {
        UIBarButtonItem *flexible = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                  target:nil
                                                                                  action:nil];
        _toolbar.items = [NSArray arrayWithObjects:_selectAllItem, flexible, _deleteItem, nil];
        [flexible release];
    }
    [view addSubview:_toolbar];

    _pathLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, frame.size.height - 22,
                                                           frame.size.width - 20, 20)];
    _pathLabel.backgroundColor = [UIColor clearColor];
    _pathLabel.font = OSSmallFont(OSIsPad() ? 13.0f : 11.0f);
    _pathLabel.textAlignment = UITextAlignmentCenter;
    _pathLabel.textColor = [UIColor colorWithWhite:0.55f alpha:1.0f];
    _pathLabel.text = OS_RECEIVED_PATH;
    _pathLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [view addSubview:_pathLabel];

    self.view = view;
    [view release];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"tab.files", nil);
    _selectedPaths = [[NSMutableSet alloc] init];

    [self updateEditButton];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(serverDidUpdate:)
                                                 name:OSServerDidUpdateNotification
                                               object:nil];
    [self reloadFiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _emptyLabel.frame = CGRectMake(40, OSIsPad() ? self.view.bounds.size.height * 0.3f : 150,
                                   self.view.bounds.size.width - 80, 60);
    [self layoutForEditing];
    [self reloadFiles];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if (OSIsPad()) return YES;
    return orientation == UIInterfaceOrientationPortrait;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation
                                         duration:(NSTimeInterval)duration {
    _emptyLabel.frame = CGRectMake(40, self.view.bounds.size.height * 0.3f,
                                   self.view.bounds.size.width - 80, 60);
    [self layoutForEditing];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    _emptyLabel.frame = CGRectMake(40, self.view.bounds.size.height * 0.3f,
                                   self.view.bounds.size.width - 80, 60);
    [self layoutForEditing];
}

- (void)serverDidUpdate:(NSNotification *)notification {
    /* Reloading while a swipe-to-delete is open closes the Delete button. */
    if (_batchEditing || _rowEditing) return;
    [self reloadFiles];
}

- (void)tableView:(UITableView *)tableView
willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    _rowEditing = YES;
}

- (void)tableView:(UITableView *)tableView
didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    _rowEditing = NO;
}

- (void)layoutForEditing {
    CGRect bounds = self.view.bounds;
    CGFloat toolbarHeight = _batchEditing ? 44.0f : 0.0f;
    CGFloat pathHeight = 22.0f;
    _tableView.frame = CGRectMake(0, 0, bounds.size.width,
                                  bounds.size.height - toolbarHeight - pathHeight);
    _pathLabel.frame = CGRectMake(10, bounds.size.height - toolbarHeight - pathHeight,
                                  bounds.size.width - 20, pathHeight);
    _toolbar.frame = CGRectMake(0, bounds.size.height - 44, bounds.size.width, 44);
}

- (void)updateEditButton {
    UIBarButtonItem *item = [[UIBarButtonItem alloc]
                             initWithBarButtonSystemItem:(_batchEditing ? UIBarButtonSystemItemDone
                                                                        : UIBarButtonSystemItemEdit)
                                                  target:self
                                                  action:@selector(toggleEditing)];
    self.navigationItem.leftBarButtonItem = nil;
    self.navigationItem.rightBarButtonItem = item;
    [item release];
}

- (void)toggleEditing {
    _batchEditing = !_batchEditing;
    [_selectedPaths removeAllObjects];
    _toolbar.hidden = !_batchEditing;

    [self updateEditButton];
    [self layoutForEditing];
    [self updateToolbar];
    [_tableView reloadData];
}

- (void)updateToolbar {
    NSUInteger selected = [_selectedPaths count];
    BOOL all = ([_files count] > 0 && selected == [_files count]);
    BOOL enabled = selected > 0;

    [_selectAllControl setTitle:(all ? NSLocalizedString(@"files.deselect_all", nil)
                                     : NSLocalizedString(@"files.select_all", nil))
              forSegmentAtIndex:0];
    [_deleteControl setTitle:[NSString stringWithFormat:
                              NSLocalizedString(@"files.delete_count", nil),
                              (int)selected]
           forSegmentAtIndex:0];
    _selectAllControl.enabled = ([_files count] > 0);
    _deleteControl.enabled = enabled;
}

- (void)selectAllTapped {
    if ([_files count] == 0) return;

    if ([_selectedPaths count] == [_files count]) {
        [_selectedPaths removeAllObjects];
    } else {
        for (NSDictionary *file in _files) {
            [_selectedPaths addObject:[file objectForKey:@"path"]];
        }
    }
    [_tableView reloadData];
    [self updateToolbar];
}

- (void)deleteSelected {
    NSUInteger selected = [_selectedPaths count];
    if (selected == 0) return;

    {
        NSString *message = [NSString stringWithFormat:
                             NSLocalizedString(@"files.delete_confirm_message", nil),
                             (int)selected];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"files.delete_confirm_title", nil)
                                                        message:message
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"common.cancel", nil)
                                              otherButtonTitles:NSLocalizedString(@"files.delete", nil), nil];
        [alert show];
        [alert release];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;

    {
        NSMutableArray *targets = [NSMutableArray array];
        BOOL failed = NO;

        for (NSDictionary *file in _files) {
            if ([_selectedPaths containsObject:[file objectForKey:@"path"]]) {
                [targets addObject:file];
            }
        }

        for (NSDictionary *file in targets) {
            if (![[OSServer shared] deleteReceivedFile:file]) {
                failed = YES;
            }
        }

        [_selectedPaths removeAllObjects];
        [self reloadFiles];

        if (failed) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"files.delete_failed_title", nil)
                                                            message:NSLocalizedString(@"files.delete_failed_message", nil)
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                                  otherButtonTitles:nil];
            [alert show];
            [alert release];
        }

        if ([_files count] == 0 && _batchEditing) {
            [self toggleEditing];
        } else {
            [self updateToolbar];
        }
    }
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

- (void)reloadFiles {
    [_files release];
    _files = [[[OSServer shared] receivedFiles] retain];

    if (_selectedPaths != nil) {
        NSMutableSet *existing = [NSMutableSet set];
        for (NSDictionary *file in _files) {
            [existing addObject:[file objectForKey:@"path"]];
        }
        [_selectedPaths intersectSet:existing];
    }

    [_tableView reloadData];
    _emptyLabel.hidden = ([_files count] > 0);
    _tableView.separatorStyle = [_files count] > 0 ? UITableViewCellSeparatorStyleSingleLine
                                                  : UITableViewCellSeparatorStyleNone;
    self.navigationItem.rightBarButtonItem.enabled = (_batchEditing || [_files count] > 0);
    if (_batchEditing) [self updateToolbar];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([_files count] == 0) return nil;
    return NSLocalizedString(@"files.header", nil);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[_files count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"FileCell";
    FileCell *cell = (FileCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[[FileCell alloc] initWithStyle:UITableViewCellStyleDefault
                                reuseIdentifier:identifier] autorelease];
    }

    {
        NSDictionary *file = [_files objectAtIndex:indexPath.row];
        long long size = [[file objectForKey:@"size"] longLongValue];
        NSString *detail = [NSString stringWithFormat:@"%@ · %@",
                            [self formatBytes:size],
                            [self formatDate:[file objectForKey:@"date"]]];
        BOOL selected = [_selectedPaths containsObject:[file objectForKey:@"path"]];
        [cell configureName:[file objectForKey:@"name"]
                     detail:detail
                    editing:_batchEditing
                   selected:selected];
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return !_batchEditing;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView
        commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
         forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    {
        NSDictionary *file = [_files objectAtIndex:indexPath.row];
        if (![[OSServer shared] deleteReceivedFile:file]) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"files.delete_failed_title", nil)
                                                            message:NSLocalizedString(@"files.delete_failed_message", nil)
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                                  otherButtonTitles:nil];
            [alert show];
            [alert release];
            return;
        }
        [self reloadFiles];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    if (_batchEditing) {
        NSDictionary *file = [_files objectAtIndex:indexPath.row];
        NSString *path = [file objectForKey:@"path"];

        if ([_selectedPaths containsObject:path]) {
            [_selectedPaths removeObject:path];
        } else {
            [_selectedPaths addObject:path];
        }
        [self reloadFiles];
        return;
    }

    {
        NSDictionary *file = [_files objectAtIndex:indexPath.row];
        long long size = [[file objectForKey:@"size"] longLongValue];
        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"files.info_message", nil),
                             [file objectForKey:@"name"],
                             [self formatBytes:size],
                             [self formatDate:[file objectForKey:@"date"]],
                             [file objectForKey:@"path"]];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"files.info_title", nil)
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                              otherButtonTitles:nil];
        [alert show];
        [alert release];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_tableView release];
    [_emptyLabel release];
    [_pathLabel release];
    [_files release];
    [_toolbar release];
    [_deleteItem release];
    [_selectAllItem release];
    [_selectAllControl release];
    [_deleteControl release];
    [_selectedPaths release];
    [super dealloc];
}

@end
