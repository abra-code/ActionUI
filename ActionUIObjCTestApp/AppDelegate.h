//
//  AppDelegate.h
//

#if __has_include(<AppKit/AppKit.h>)
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

@interface AppDelegate :
#if __has_include(<AppKit/AppKit.h>)
NSObject <NSApplicationDelegate>
#else
NSObject <UIApplicationDelegate>
#endif

@end

