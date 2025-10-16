//
//  ObjCLogger.m
//

#import "ObjCLogger.h"

@implementation ObjCLogger
- (void)logMessage:(NSString *)message level:(NSInteger)level {
    
    static NSArray *levelMap = @[
        @"error", // 1
        @"warning", // 2
        @"info", // 3
        @"debug", // 4
        @"verbose" // 5
    ];
    
    NSString *levelStr = ((level >= 1) && (level<= 5)) ? levelMap[level-1] : @"unknown";
    
    NSLog(@"[ActionUI][%@] %@", levelStr, message);
}
@end
