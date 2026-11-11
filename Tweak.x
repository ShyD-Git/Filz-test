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

// --- 1. Bắt Dữ Liệu Mạng (Bọc @try @catch chống crash) ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && request.URL) {
            NSString *urlStr = request.URL.absoluteString;
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            
            if ([urlStr containsString:@"session"] || [urlStr containsString:@"user"] || 
                [urlStr containsString:@"premium"] || [urlStr containsString:@"activate"] || 
                [urlStr containsString:@"temp"]) {
                
                qaLog(@"📡 API RAW: %@\nBODY: %@", urlStr, jsonStr);
                
                @try {
                    if (jsonStr) {
                        NSMutableString *mutStr = [jsonStr mutableCopy];
                        [mutStr replaceOccurrencesOfString:@"\"premium\":false" withString:@"\"premium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                        [mutStr replaceOccurrencesOfString:@"\"is_premium\":false" withString:@"\"is_premium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                        [mutStr replaceOccurrencesOfString:@"\"isPremium\":false" withString:@"\"isPremium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                        [mutStr replaceOccurrencesOfString:@"\"active\":false" withString:@"\"active\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                        [mutStr replaceOccurrencesOfString:@"\"isActive\":false" withString:@"\"isActive\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                        [mutStr replaceOccurrencesOfString:@"\"subscribed\":false" withString:@"\"subscribed\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                        
                        if (![mutStr isEqualToString:jsonStr]) {
                            qaLog(@"✂️ Đã đổi cờ Premium thành TRUE");
                            data = [mutStr dataUsingEncoding:NSUTF8StringEncoding];
                        }
                    }
                } @catch (NSException *e) {
                    qaLog(@"❌ Lỗi chuyển đổi JSON: %@", e.reason);
                }
            }
        }
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    return %orig(request, wrappedCompletion);
}
%end

// --- 2. Hook NSUserDefaults (Chỉ hook boolForKey, ĐÉO hook objectForKey) ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
        return NO;
    }
    if ([lower containsString:@"premium"] || [lower containsString:@"pro"] || 
        [lower containsString:@"active"] || [lower containsString:@"sub"] || 
        [lower containsString:@"vip"] || [lower containsString:@"paid"] ||
        [lower containsString:@"unlocked"]) {
        qaLog(@"✅ Ép TRUE Defaults: %@", defaultName);
        return YES;
    }
    return %orig;
}
%end

// --- 3. Xử lý nút bấm Paywall (Tự động gọi Restore Purchases) ---
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *clsName = NSStringFromClass([self class]).lowercaseString;
    if ([clsName containsString:@"trypremium"]) {
        qaLog(@"🚀 Đang ở màn hình Paywall, tìm nút Restore...");
        
        // Quét tìm nút Khôi phục để bấm hộ
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            for (UIView *view in self.view.subviews) {
                if ([view isKindOfClass:[UIButton class]]) {
                    UIButton *btn = (UIButton *)view;
                    if ([btn.titleLabel.text containsString:@"Khôi phục"] || 
                        [btn.titleLabel.text containsString:@"Restore"]) {
                        qaLog(@"👉 Đã tìm thấy nút Khôi phục, tự động bấm!");
                        [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                        break;
                    }
                }
            }
        });
    }
}
%end

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Safe Network & No ObjectForKey)");
}
