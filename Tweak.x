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
    dispatch_once(&onceToken, ^{
        logQueue = dispatch_queue_create("qa.log.queue", DISPATCH_QUEUE_SERIAL);
    });
    
    dispatch_async(logQueue, ^{
        NSString *path = qaLogPath();
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fileHandle == nil) {
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fileHandle closeFile];
        }
    });
}

// --- 1. Giả Lập App Store Receipt ---
%hook NSBundle
- (NSURL *)appStoreReceiptURL {
    NSURL *originalURL = %orig;
    if (originalURL) return originalURL;
    
    // Tạo file receipt giả nếu chưa có
    NSString *docsDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *fakeReceiptPath = [docsDir stringByAppendingPathComponent:@"fake_receipt"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:fakeReceiptPath]) {
        // Một chuỗi JSON giả lập App Store Receipt
        NSString *fakeReceiptJSON = @"{\"status\":0,\"environment\":\"Production\",\"receipt\":{\"bundle_id\":\"com.tempmail.ios\",\"in_app\":[{\"product_id\":\"com.tempmail.ios.premium.year\",\"purchase_date_ms\":\"1700000000000\"}]}}";
        [fakeReceiptJSON writeToFile:fakeReceiptPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        qaLog(@"🛠 Đã tạo fake receipt tại: %@", fakeReceiptPath);
    }
    
    return [NSURL fileURLWithPath:fakeReceiptPath];
}
%end

// --- 2. Chặn triệt để Swift Paywall Controller ---
static void hidePaywallView(UIViewController *self) {
    NSString *clsName = NSStringFromClass([self class]).lowercaseString;
    if ([clsName containsString:@"trypremium"] || [clsName containsString:@"paywall"]) {
        qaLog(@"🛑 Phát hiện Paywall, đang tắt...");
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:^{
                // Sau khi tắt, gọi hàm mua hoặc ép cờ Premium
                qaLog(@"✅ Đã tắt Paywall.");
            }];
        });
    }
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    hidePaywallView(self);
}
%end

// --- 3. Sửa logic UserDefaults (Chỉ ép Bool, không can thiệp String) ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
        return NO;
    }
    if ([lower containsString:@"paid"] || [lower containsString:@"premium"] || [lower containsString:@"enabled"] || [lower containsString:@"pro"]) {
        return YES;
    }
    return %orig;
}
%end

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Fake Receipt & Auto Dismiss)");
}
