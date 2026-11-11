#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *qaLogPath() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"QATestingUtils.log"];
}

static void qaLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *timeString = [formatter stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timeString, msg];
    
    static dispatch_queue_t logQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        logQueue = dispatch_queue_create("com.qa.log", DISPATCH_QUEUE_SERIAL);
    });
    
    dispatch_async(logQueue, ^{
        if (![[NSFileManager defaultManager] fileExistsAtPath:qaLogPath()]) {
            [line writeToFile:qaLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:qaLogPath()];
            if (fileHandle) {
                [fileHandle seekToEndOfFile];
                [fileHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [fileHandle closeFile];
            }
        }
    });
}

%hook NSUserDefaults
- (id)objectForKey:(NSString *)defaultName {
    // CHỈ ép đúng 2 key này, không log gì cả để tránh nghẽn app
    if ([defaultName isEqualToString:@"paid_v2_user_enabled"]) {
        return @YES;
    }
    if ([defaultName isEqualToString:@"ApplicationCoordinator.keyPremiumTrialUsed"]) {
        return @NO;
    }
    return %orig;
}

- (BOOL)boolForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"paid_v2_user_enabled"]) {
        return YES;
    }
    if ([defaultName isEqualToString:@"ApplicationCoordinator.keyPremiumTrialUsed"]) {
        return NO;
    }
    return %orig;
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"paid_v2_user_enabled"]) {
        %orig(YES, defaultName);
        return;
    }
    if ([defaultName isEqualToString:@"ApplicationCoordinator.keyPremiumTrialUsed"]) {
        %orig(NO, defaultName);
        return;
    }
    %orig;
}
%end

// Chặn đứng màn hình Paywall nếu nó tự hiện
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *clsName = NSStringFromClass([self class]).lowercaseString;
    if ([clsName containsString:@"trypremium"] || [clsName containsString:@"paywall"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    }
}
%end

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (No Log Getter, App Alive)");
}
