#import <UIKit/UIKit.h>

@interface SettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate> {
    UITableView *_tableView;
    UITextField *_nicknameField;
    UIButton *_randomButton;
    UISwitch *_quickSaveSwitch;
}

@end
