//
//  AppDelegate.m
//

#import "AppDelegate.h"

@import ActionUIObjCAdapter;

typedef void (^ActionUIObjCActionHandlerBlock)(NSString *_Nonnull actionID, NSString *_Nonnull windowUUID, NSInteger viewID, NSInteger viewPartID, id _Nullable context);

@interface ObjCLogger : NSObject <ActionUIObjCLogger>
@end

@implementation ObjCLogger
- (void)logMessage:(NSString *)message level:(NSInteger)level {
    NSLog(@"[%ld] %@", level, message);
}
@end

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
}
#else
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    [ActionUIObjC setLogger:[[ObjCLogger alloc] init]];
    [ActionUIObjC registerActionHandlerForActionID:@"action.handle" handler:^(NSString *actionID, NSString *windowUUID, NSInteger viewID, NSInteger viewPartID, id _Nullable actionContext) {
        NSLog(@"Received action callback for actionID: %@, windowUUID: %@, viewID: %ld, viewPartID: %ld, context: %@", actionID, windowUUID, (long)viewID, (long)viewPartID, actionContext);
    }];
    return YES;
}
#endif

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


#pragma mark - UISceneSession lifecycle

#if __has_include(<UIKit/UIKit.h>)

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}

#endif // __has_include(<UIKit/UIKit.h>)


@end
