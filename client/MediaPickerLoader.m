#import "MediaPickerLoader.h"
#include <dlfcn.h>

static void *OSAssetImporterHandle(void) {
    static void *handle = NULL;
    static BOOL tried = NO;

    if (!tried) {
        NSString *path;
        tried = YES;
        path = [[NSBundle mainBundle] pathForResource:@"AssetImporter" ofType:@"dylib"];
        if (path != nil) {
            handle = dlopen([path fileSystemRepresentation], RTLD_LAZY);
        }
    }
    return handle;
}

NSArray *OSExportAssetURLs(NSArray *urls, NSString *directory) {
    typedef NSArray *(*ExportFn)(NSArray *, NSString *);
    static ExportFn function = NULL;
    static BOOL tried = NO;
    void *handle;

    if (!tried) {
        tried = YES;
        handle = OSAssetImporterHandle();
        if (handle != NULL) {
            function = (ExportFn)dlsym(handle, "OSExportAssetURLs");
        }
    }
    if (function == NULL) return nil;
    return function(urls, directory);
}

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
