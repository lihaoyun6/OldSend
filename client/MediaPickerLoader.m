#import "MediaPickerLoader.h"
#include <dlfcn.h>

Class OSLoadMediaPickerClass(void) {
    static Class pickerClass = Nil;
    static BOOL tried = NO;

    if (!tried) {
        NSString *path;
        tried = YES;
        path = [[NSBundle mainBundle] pathForResource:@"MediaPicker" ofType:@"dylib"];
        if (path != nil &&
            dlopen([path fileSystemRepresentation], RTLD_LAZY) != NULL) {
            pickerClass = NSClassFromString(@"MediaPickerViewController");
        }
    }
    return pickerClass;
}
