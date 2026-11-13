#import <Foundation/Foundation.h>

/* Loads MediaPicker.dylib (armv7 / iOS 4+) on demand. Returns Nil on iOS 3
   or when the dylib is missing, so callers can fall back to UIImagePicker. */
Class OSLoadMediaPickerClass(void);

/* Exports assets-library URLs to files in directory (iOS 4+ only). */
NSArray *OSExportAssetURLs(NSArray *urls, NSString *directory);
