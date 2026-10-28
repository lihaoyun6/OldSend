#import <UIKit/UIKit.h>
#import "TextInputViewController.h"
#import "SendFilePickerViewController.h"
#import "MediaPickerViewController.h"

@interface SendViewController : UIViewController <UITableViewDataSource, UITableViewDelegate,
                                                   UIActionSheetDelegate,
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
}

@end
