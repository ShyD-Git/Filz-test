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

// --- 1. Camera Mạng: Chỉ Log, Không Can Thiệp ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSString *urlStr = request.URL.absoluteString;
            NSString *bodyStr = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
            NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            
            // Bỏ qua mấy API rác của Google/Firebase
            if (![urlStr containsString:@"google"] && ![urlStr containsString:@"appsflyer"]) {
                qaLog(@"🚀 REQ: %@", urlStr);
                if (bodyStr) qaLog(@"   BODY: %@", bodyStr);
                qaLog(@"📥 RES: %@", respStr);
            }
        }
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    return %orig(request, wrappedCompletion);
}
%end

// --- 2. Ép Cờ Bool (Giữ nguyên) ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) return NO;
    if ([lower containsString:@"paid"] || [lower containsString:@"premium"] || [lower containsString:@"enabled"] || [lower containsString:@"pro"]) {
        return YES;
    }
    return %orig;
}
%end

// --- 3. Chặn Paywall (Giữ nguyên) ---
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
    qaLog(@"🚀 QATestingUtils Loaded (Network Camera)");
}
