#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <StoreKit/StoreKit.h>

static NSString *qaLogPath() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"QATestingUtils.log"];
}

static void qaLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *time = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", time, msg];
    static dispatch_queue_t logQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ logQueue = dispatch_queue_create("qa.log", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(logQueue, ^{
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:qaLogPath()];
        if (fh == nil) [line writeToFile:qaLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        else { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    });
}

// --- 1. Chặn Ghi Đè & Ép Cờ Premium ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) return NO;
    if ([lower containsString:@"paid"] || [lower containsString:@"premium"] || [lower containsString:@"pro"]) return YES;
    return %orig;
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    
    // Nếu app cố gắng set trialused = YES hoặc premium = NO -> Đấm lại
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
        %orig(NO, defaultName);
        return;
    }
    if ([lower containsString:@"paid"] || [lower containsString:@"premium"] || [lower containsString:@"pro"]) {
        %orig(YES, defaultName);
        return;
    }
    %orig;
}

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
        %orig(@NO, defaultName);
        return;
    }
    if ([lower containsString:@"paid"] || [lower containsString:@"premium"] || [lower containsString:@"pro"]) {
        %orig(@YES, defaultName);
        return;
    }
    %orig;
}
%end

// --- 2. Bơm Receipt Giả (Tránh kẹt vòng lặp nil) ---
%hook NSBundle
- (NSURL *)appStoreReceiptURL {
    NSString *docsDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *fakePath = [docsDir stringByAppendingPathComponent:@"fake_receipt"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:fakePath]) {
        NSString *fakeJWS = @"{\"status\":0,\"environment\":\"Production\",\"receipt\":{\"bundle_id\":\"com.tempmail.ios\",\"in_app\":[{\"product_id\":\"premium_monthly\",\"purchase_date_ms\":\"1700000000000\"}]}}";
        [fakeJWS writeToFile:fakePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return [NSURL fileURLWithPath:fakePath];
}
%end

// --- 3. Chặn đứng Paywall ---
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *clsName = NSStringFromClass([self class]).lowercaseString;
    if ([clsName containsString:@"trypremium"] || [clsName containsString:@"paywall"]) {
        qaLog(@"🛑 Đá văng Paywall: %@", clsName);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    }
}
%end

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Block Overrides & Force Premium)");
}
