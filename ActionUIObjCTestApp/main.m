//
//  main.m
//  ActionUIObjCTestApp
//

#if __has_include(<AppKit/AppKit.h>)
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

#import "AppDelegate.h"

int main(int argc, char *argv[])
{
#if __has_include(<AppKit/AppKit.h>)
    return NSApplicationMain(argc,  (const char **) argv);
#else
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
#endif
}
