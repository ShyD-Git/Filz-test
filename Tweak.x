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

// --- 1. Bơm Session ID Giả & Ép Cờ Premium ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    if ([defaultName containsString:@"trialused"] || [defaultName containsString:@"expired"]) return NO;
    if ([defaultName isEqualToString:@"paid_v2_user_enabled"] || [defaultName containsString:@"premium"] || [defaultName containsString:@"pro"]) {
        return YES;
    }
    return %orig;
}

- (id)objectForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"ApplicationCoordinator.keyPremiumSessionId"] || 
        [defaultName isEqualToString:@"ApplicationCoordinator.keyPremiumSessionIdCached"]) {
        qaLog(@"💉 Bơm Session ID: %@", defaultName);
        return @"602BFAEF-EBF5-478D-878B-FC0149D1BC2E";
    }
    return %orig;
}

- (NSString *)stringForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"ApplicationCoordinator.keyPremiumSessionId"] || 
        [defaultName isEqualToString:@"ApplicationCoordinator.keyPremiumSessionIdCached"]) {
        qaLog(@"💉 Bơm String Session ID: %@", defaultName);
        return @"602BFAEF-EBF5-478D-878B-FC0149D1BC2E";
    }
    return %orig;
}
%end

// --- 2. Bắt Mạng & Nặn Data Pro ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *urlStr = request.URL.absoluteString;
        
        // Chặn API Premium và trả data giả
        if ([urlStr containsString:@"premium"] || [urlStr containsString:@"session"] || [urlStr containsString:@"domain"]) {
            qaLog(@"🛑 Chặn API: %@", urlStr);
            
            // Trả về JSON giả báo thành công
            NSString *fakeJSON = @"{\"status\":\"success\",\"is_premium\":true,\"isActive\":true,\"session_id\":\"602BFAEF-EBF5-478D-878B-FC0149D1BC2E\",\"domains\":[\"@orsonki.com\"],\"mailbox\":\"jixowo7289@orsonki.com\"}";
            data = [fakeJSON dataUsingEncoding:NSUTF8StringEncoding];
            response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        } else if (data) {
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (jsonStr.length > 0 && jsonStr.length < 2000) {
                qaLog(@"📡 URL: %@\nBODY: %@", urlStr, jsonStr);
                // Đổi cờ false thành true
                NSMutableString *mutStr = [jsonStr mutableCopy];
                [mutStr replaceOccurrencesOfString:@"\"premium\":false" withString:@"\"premium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                [mutStr replaceOccurrencesOfString:@"\"isActive\":false" withString:@"\"isActive\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                if (![mutStr isEqualToString:jsonStr]) data = [mutStr dataUsingEncoding:NSUTF8StringEncoding];
            }
        }
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrapped);
}
%end

// --- 3. Chặn Paywall ---
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *clsName = NSStringFromClass([self class]).lowercaseString;
    if ([clsName containsString:@"trypremium"] || [clsName containsString:@"paywall"]) {
        qaLog(@"🛑 Chặn Paywall: %@", clsName);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    }
}
%end

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Inject Session & Mock API)");
}
