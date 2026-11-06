#import <UIKit/UIKit.h>
#import "TextInputViewController.h"
#import "SendFilePickerViewController.h"
#import "MediaPickerViewController.h"

@interface SendViewController : UIViewController <UITableViewDataSource, UITableViewDelegate,
                                                   UIActionSheetDelegate,
                                                   UIAlertViewDelegate,
                                                   UIImagePickerControllerDelegate,
                                                   UINavigationControllerDelegate,
                                                   TextInputViewControllerDelegate,
                                                   SendFilePickerDelegate,
                                                   MediaPickerDelegate> {
    UITableView *_tableView;
    UILabel *_emptyLabel;
    UIBarButtonItem *_addButton;
    NSMutableArray *_pendingItems;
    id _mediaPopover;
    UIActionSheet *_typeSheet;
    BOOL _shareMode;
    NSMutableArray *_shareImportedPaths;
    NSString *_returnBundleIdentifier;
}

- (void)addPendingFilePath:(NSString *)path;
- (void)addPendingText:(NSString *)text;
- (void)enableShareMode;
- (void)setReturnBundleIdentifier:(NSString *)bundleIdentifier;

@end
