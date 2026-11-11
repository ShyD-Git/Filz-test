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

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Direct Injection)");
    
    // Chờ 0.5s để app khởi tạo UserDefaults rồi tiêm thẳng giá trị vào
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        // 1. Bơm Session ID
        NSString *fakeUUID = @"602BFAEF-EBF5-478D-878B-FC0149D1BC2E";
        [defaults setObject:fakeUUID forKey:@"ApplicationCoordinator.keyPremiumSessionId"];
        [defaults setObject:fakeUUID forKey:@"ApplicationCoordinator.keyPremiumSessionIdCached"];
        [defaults setObject:fakeUUID forKey:@"paid"];
        [defaults setObject:fakeUUID forKey:@"paid_v2"];
        
        // 2. Bơm Receipt giả
        [defaults setObject:@"MIIbBAYJKoZIhvcNAQcCoIIb..." forKey:@"ApplicationCoordinator.keyPremiumPurchaseReceipt"];
        
        // 3. Bơm Timestamp
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ss Z"];
        [defaults setObject:[df stringFromDate:[NSDate date]] forKey:@"paid_timestamp"];
        [defaults setObject:[df stringFromDate:[NSDate date]] forKey:@"paid_v2_timestamp"];
        
        // 4. Bật cờ Premium
        [defaults setBool:YES forKey:@"paid_v2_user_enabled"];
        [defaults setBool:YES forKey:@"UserInterfaceOverrider.endpointPremiumDev"];
        [defaults setBool:NO forKey:@"ApplicationCoordinator.keyPremiumTrialUsed"];
        
        // Đồng bộ xuống đĩa
        [defaults synchronize];
        
        qaLog(@"💉 Đã tiêm toàn bộ dữ liệu Premium vào UserDefaults!");
    });
}

// Chặn Paywall nếu nó vẫn cố tình nhảy ra
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
