#import <UIKit/UIKit.h>

@protocol MediaPickerDelegate <NSObject>
- (void)mediaPicker:(id)picker didFinishWithItems:(NSArray *)items;
- (void)mediaPickerDidCancel:(id)picker;
@end

@interface MediaPickerViewController : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    NSMutableArray *_assets;
    NSMutableArray *_loadingAssets;
    id _library;
    NSMutableSet *_selectedIndexes;
    UIActivityIndicatorView *_spinner;
    UILabel *_emptyLabel;
    id<MediaPickerDelegate> _delegate;
    BOOL _loading;
    NSInteger _previewIndex;
    BOOL _previewWasSelected;
    BOOL _exporting;
    UIView *_exportHUD;
}

@property (nonatomic, assign) id<MediaPickerDelegate> delegate;

@end
