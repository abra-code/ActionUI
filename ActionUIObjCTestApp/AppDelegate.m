//
//  AppDelegate.m
//

#import "AppDelegate.h"
#import "ObjCLogger.h"

@import ActionUIObjCAdapter;

typedef void (^ActionUIObjCActionHandlerBlock)(NSString *_Nonnull actionID, NSString *_Nonnull windowUUID, NSInteger viewID, NSInteger viewPartID, id _Nullable context);

@interface AppDelegate ()

#if __has_include(<AppKit/AppKit.h>)
@property (weak) IBOutlet NSWindow *window;
#endif
@end

@implementation AppDelegate

#if __has_include(<AppKit/AppKit.h>)
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [ActionUIObjC setLogger:[[ObjCLogger alloc] init]];
    [ActionUIObjC registerActionHandlerForActionID:@"action.handle" handler:^(NSString *actionID, NSString *windowUUID, NSInteger viewID, NSInteger viewPartID, id _Nullable actionContext) {
        NSLog(@"Received action callback for actionID: %@, windowUUID: %@, viewID: %ld, viewPartID: %ld, context: %@", actionID, windowUUID, (long)viewID, (long)viewPartID, actionContext);
    }];
    
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"DefaultWindowContentView" withExtension:@"json"];
    NSString *windowUUID = [[NSUUID UUID] UUIDString];
    NSViewController *controller = [ActionUIObjC loadHostingControllerWithURL:url windowUUID:windowUUID isContentView:YES];
    self.window.contentViewController = controller;
    
    // Set window size based on the SwiftUI view's fitting size, with a minimum threshold and fallback
    NSSize fittingSize = controller.view.fittingSize;
    NSLog(@"Fitting size: %f x %f", fittingSize.width, fittingSize.height);
    NSSize windowSize = (fittingSize.width >= 10 && fittingSize.height >= 10) ? fittingSize : NSMakeSize(480, 320);
    [self.window setContentSize:windowSize];
    
    // Ensure window is resizable and set min size
    self.window.styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
//    [self.window setContentMinSize:NSMakeSize(400, 300)]; // Prevent window from being too small
    
    [self.window center]; // Center the window on screen
    [self.window makeKeyAndOrderFront:nil];
    
    // Log final window state for debugging
    NSLog(@"Window frame: %f x %f, styleMask: %ld", self.window.frame.size.width, self.window.frame.size.height, (long)self.window.styleMask);
}
#else
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // No UI setup needed here; handled in SceneDelegate.m
    return YES;
}
#endif

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

#pragma mark - UISceneSession lifecycle

#if __has_include(<UIKit/UIKit.h>)

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Release any resources specific to discarded scenes
}

#endif // __has_include(<UIKit/UIKit.h>)

@end
