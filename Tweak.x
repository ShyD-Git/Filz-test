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

// --- 1. Bắt toàn bộ JSON trả về từ Server ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            // Chỉ log những API có chữ session, user, premium, hoặc response ngắn
            if ([request.URL.absoluteString containsString:@"session"] || 
                [request.URL.absoluteString containsString:@"user"] || 
                [request.URL.absoluteString containsString:@"premium"] ||
                [request.URL.absoluteString containsString:@"activation"]) {
                
                qaLog(@"🌐 API RESPONSE: %@\nDATA: %@", request.URL.absoluteString, jsonString);
            }
        }
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    return %orig(request, wrappedCompletion);
}
%end

// --- 2. Chặn bảng thanh toán ---
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

// --- 3. Ép cờ Trial về FALSE ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
        return NO;
    }
    return %orig;
}
%end

// --- 4. Lục lọi Class Swift (Dump Methods) ---
static void dumpMethods() {
    NSArray *classesToDump = @[
        @"TempMailPremiumAPI.UserSessionResultClass",
        @"TempMailPremiumAPI.UserSessionResponseParser",
        @"TempMailPremiumAPI.APIUserSessionRequest"
    ];
    
    for (NSString *clsName in classesToDump) {
        Class cls = objc_getClass([clsName UTF8String]);
        if (!cls) continue;
        
        qaLog(@"🔍 Dump Methods của %@:", clsName);
        unsigned int count;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            qaLog(@"   🔑 Method: %s", sel_getName(sel));
        }
        free(methods);
    }
}

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Network & Method Dumper)");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dumpMethods();
    });
}
