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

// --- 1. Chỉ Ép Cờ Boolean (Đéo đụng Object/String) ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) return NO;
    
    if ([lower containsString:@"paid"] || 
        [lower containsString:@"premium"] || 
        [lower containsString:@"enabled"] || 
        [lower containsString:@"pro"] ||
        [lower containsString:@"endpointpremiumdev"]) {
        qaLog(@"✅ Ép TRUE: %@", defaultName);
        return YES;
    }
    return %orig;
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
        %orig(NO, defaultName);
        return;
    }
    if ([lower containsString:@"paid"] || 
        [lower containsString:@"premium"] || 
        [lower containsString:@"enabled"] || 
        [lower containsString:@"pro"] ||
        [lower containsString:@"endpointpremiumdev"]) {
        %orig(YES, defaultName);
        return;
    }
    %orig;
}
%end

// --- 2. Sửa Mạng Bằng Chuỗi String (Không dùng Object) ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (jsonStr) {
                @try {
                    NSMutableString *mutStr = [jsonStr mutableCopy];
                    // Quét các cờ false trong JSON của server thành true
                    [mutStr replaceOccurrencesOfString:@"\"premium\":false" withString:@"\"premium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"isPremium\":false" withString:@"\"isPremium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"is_premium\":false" withString:@"\"is_premium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"active\":false" withString:@"\"active\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"isActive\":false" withString:@"\"isActive\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"subscribed\":false" withString:@"\"subscribed\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    
                    if (![mutStr isEqualToString:jsonStr]) {
                        qaLog(@"✂️ Đã sửa JSON server trả về");
                        data = [mutStr dataUsingEncoding:NSUTF8StringEncoding];
                    }
                } @catch (NSException *e) {}
            }
        }
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    return %orig(request, wrappedCompletion);
}
%end

// --- 3. Đá Văng Paywall ---
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
    qaLog(@"🚀 QATestingUtils Loaded (Safe Loop Fix)");
}
