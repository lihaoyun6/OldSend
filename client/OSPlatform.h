#import <UIKit/UIKit.h>

/* YES on iPad, including iPad 1 running iPhone OS 3.2 / 4.x. */
BOOL OSIsPad(void);

/* Small hint text: bold on iPad, regular on iPhone/iPod. */
UIFont *OSSmallFont(CGFloat size);
