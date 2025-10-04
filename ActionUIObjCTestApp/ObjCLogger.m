//
//  ObjCLogger.m
//

#import "ObjCLogger.h"

@implementation ObjCLogger
- (void)logMessage:(NSString *)message level:(NSInteger)level {
    NSLog(@"[%ld] %@", level, message);
}
@end
