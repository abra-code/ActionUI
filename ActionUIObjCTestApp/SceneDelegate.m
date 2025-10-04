//
//  SceneDelegate.m
//

#import "SceneDelegate.h"
#import "ObjCLogger.h"
@import ActionUIObjCAdapter;

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    // Configure and attach the UIWindow to the provided UIWindowScene.
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
        
        // Set up logger and action handler
        [ActionUIObjC setLogger:[[ObjCLogger alloc] init]];
        [ActionUIObjC registerActionHandlerForActionID:@"action.handle" handler:^(NSString *actionID, NSString *windowUUID, NSInteger viewID, NSInteger viewPartID, id _Nullable actionContext) {
            NSLog(@"Received action callback for actionID: %@, windowUUID: %@, viewID: %ld, viewPartID: %ld, context: %@", actionID, windowUUID, (long)viewID, (long)viewPartID, actionContext);
        }];
        
        // Load JSON from bundle and create view controller
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"DefaultWindowContentView" withExtension:@"json"];
        NSString *windowUUID = [[NSUUID UUID] UUIDString];
        UIViewController *controller = [ActionUIObjC loadHostingControllerWithURL:url windowUUID:windowUUID isContentView:YES];
        
        // Wrap in a navigation controller and set as root
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
        self.window.rootViewController = navController;
        [self.window makeKeyAndVisible];
    }
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    // Called as the scene is being released by the system.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    // Called when the scene has moved from an inactive state to an active state.
    // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
}

- (void)sceneWillResignActive:(UIScene *)scene {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (e.g., an incoming phone call).
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.
}

@end
