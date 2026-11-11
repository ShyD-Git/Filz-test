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
    NSString *lower = defaultName.lowercaseString;
    
    // 1. Cờ Boolean (báo đã mua)
    if ([lower containsString:@"paid_v2_user_enabled"] || [lower containsString:@"endpointpremiumdev"]) {
        qaLog(@"💉 Ép @YES: %@", defaultName);
        return @YES;
    }
    
    // 2. Receipt (Phải là Base64, không phải UUID)
    if ([lower containsString:@"receipt"]) {
        qaLog(@"💉 Ép Receipt Base64: %@", defaultName);
        return @"MIIbBAYJKoZIhvcNAQcCoIIb...";
    }
    
    // 3. Session ID / paid / paid_v2 (Phải là UUID)
    if ([lower containsString:@"sessionid"] || [lower isEqualToString:@"paid"] || [lower isEqualToString:@"paid_v2"]) {
        qaLog(@"💉 Ép UUID: %@", defaultName);
        return @"602BFAEF-EBF5-478D-878B-FC0149D1BC2E";
    }
    
    // 4. Timestamp
    if ([lower containsString:@"timestamp"]) {
        return @"2099-12-31 23:59:59 +0000";
    }
    
    // 5. Chặn cờ trial
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
        return @NO;
    }
    
    return %orig;
}

- (NSString *)stringForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"receipt"]) return @"MIIbBAYJKoZIhvcNAQcCoIIb...";
    if ([lower containsString:@"sessionid"] || [lower isEqualToString:@"paid"] || [lower isEqualToString:@"paid_v2"]) return @"602BFAEF-EBF5-478D-878B-FC0149D1BC2E";
    if ([lower containsString:@"timestamp"]) return @"2099-12-31 23:59:59 +0000";
    return %orig;
}

- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) return NO;
    if ([lower containsString:@"paid"] || [lower containsString:@"premium"] || [lower containsString:@"enabled"] || [lower containsString:@"pro"]) return YES;
    return %orig;
}
%end

// Chặn đứng màn hình Paywall
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *clsName = NSStringFromClass([self class]).lowercaseString;
    if ([clsName containsString:@"trypremium"] || [clsName containsString:@"paywall"]) {
        qaLog(@"🛑 Chặn Paywall: %@", clsName);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    }
}
%end

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Typed Overrides)");
}
