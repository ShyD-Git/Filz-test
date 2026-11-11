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

// --- 1. Bắt Dữ Liệu Mạng (Sửa chuỗi JSON thay vì dùng Object) ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && request.URL) {
            NSString *urlStr = request.URL.absoluteString;
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            
            // Chỉ log và can thiệp nếu là API của app
            if ([urlStr containsString:@"session"] || [urlStr containsString:@"user"] || 
                [urlStr containsString:@"premium"] || [urlStr containsString:@"activate"]) {
                
                qaLog(@"📡 API RAW: %@\nBODY: %@", urlStr, jsonStr);
                
                if (jsonStr) {
                    NSMutableString *mutStr = [jsonStr mutableCopy];
                    // Thay thế cờ false thành true (Không phân biệt hoa thường)
                    [mutStr replaceOccurrencesOfString:@"\"premium\":false" withString:@"\"premium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"is_premium\":false" withString:@"\"is_premium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"isPremium\":false" withString:@"\"isPremium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"active\":false" withString:@"\"active\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"isActive\":false" withString:@"\"isActive\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"subscribed\":false" withString:@"\"subscribed\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"is_subscribed\":false" withString:@"\"is_subscribed\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    
                    if (![mutStr isEqualToString:jsonStr]) {
                        qaLog(@"✂️ Đã đổi cờ Premium thành TRUE trong JSON");
                        data = [mutStr dataUsingEncoding:NSUTF8StringEncoding];
                    }
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

// --- 2. Hook NSUserDefaults (Sửa cờ Local) ---
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

- (id)objectForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"premium"] || [lower containsString:@"pro"] || 
        [lower containsString:@"active"] || [lower containsString:@"sub"]) {
        return @(YES);
    }
    return %orig;
}
%end

// --- 3. Chặn Paywall ---
%hook UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    NSString *clsName = NSStringFromClass([viewControllerToPresent class]).lowercaseString;
    if ([clsName containsString:@"trypremium"] || [clsName containsString:@"paywall"]) {
        qaLog(@"🛑 Chặn Paywall: %@", clsName);
        if (completion) completion();
        return;
    }
    %orig;
}
%end

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Safe Network Intercept)");
}
