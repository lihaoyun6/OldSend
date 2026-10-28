#import <UIKit/UIKit.h>

@class SendFilePickerViewController;

@protocol SendFilePickerDelegate <NSObject>
- (void)sendFilePicker:(SendFilePickerViewController *)picker
         didSelectFile:(NSString *)path
                  name:(NSString *)name
                  size:(long long)size;
- (void)sendFilePickerDidCancel:(SendFilePickerViewController *)picker;
@end

@interface SendFilePickerViewController : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    UILabel *_emptyLabel;
    UILabel *_pathLabel;
    NSArray *_entries;
    NSString *_currentPath;
    NSMutableSet *_selectedPaths;
    id<SendFilePickerDelegate> _delegate;
}

@property (nonatomic, assign) id<SendFilePickerDelegate> delegate;

@end
