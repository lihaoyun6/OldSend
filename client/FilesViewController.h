#import <UIKit/UIKit.h>

@interface FilesViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate> {
    UITableView *_tableView;
    UILabel *_emptyLabel;
    UILabel *_pathLabel;
    NSArray *_files;
    UIToolbar *_toolbar;
    UIBarButtonItem *_deleteItem;
    UIBarButtonItem *_selectAllItem;
    UISegmentedControl *_deleteControl;
    UISegmentedControl *_selectAllControl;
    NSMutableSet *_selectedPaths;
    BOOL _batchEditing;
    BOOL _rowEditing;
}

@end
