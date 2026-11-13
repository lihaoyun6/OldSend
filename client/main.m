#import <UIKit/UIKit.h>
#import "AppDelegate.h"

static void OSApplySystemLanguage(void) {
    NSDictionary *global = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/.GlobalPreferences.plist"];
    NSArray *languages = [global objectForKey:@"AppleLanguages"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *current = [defaults objectForKey:@"AppleLanguages"];

    if ([languages isKindOfClass:[NSArray class]] && [languages count] > 0 &&
        ![current isEqualToArray:languages]) {
        [defaults setObject:languages forKey:@"AppleLanguages"];
        [defaults synchronize];
    }
}

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    OSApplySystemLanguage();
    int ret = UIApplicationMain(argc, argv, nil, @"AppDelegate");
    [pool release];
    return ret;
}
