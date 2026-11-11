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

// --- 1. Giả Lập JWS Receipt Cho StoreKit 2 ---
%hook NSBundle
- (NSURL *)appStoreReceiptURL {
    NSString *docsDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *fakePath = [docsDir stringByAppendingPathComponent:@"fake_receipt"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:fakePath]) {
        // Chuỗi JSON giả lập JWS (Payload chứa thông tin Premium)
        NSString *fakeJWS = @"{\"status\":0,\"environment\":\"Production\",\"receipt\":{\"bundle_id\":\"com.tempmail.ios\",\"in_app\":[{\"product_id\":\"premium_monthly\",\"purchase_date_ms\":\"1700000000000\"}]}}";
        [fakeJWS writeToFile:fakePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return [NSURL fileURLWithPath:fakePath];
}
%end

// --- 2. Hook StoreKit 2 (Ép hàm check quyền trả về True) ---
static void patchStoreKit2() {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        NSString *clsName = NSStringFromClass(cls);
        
        if ([clsName containsString:@"StoreKit"] && ([clsName containsString:@"Transaction"] || [clsName containsString:@"Entitlement"])) {
            qaLog(@"🎯 Móc StoreKit 2: %@", clsName);
            unsigned int mCount;
            Method *methods = class_copyMethodList(cls, &mCount);
            for (unsigned int j = 0; j < mCount; j++) {
                Method m = methods[j];
                SEL sel = method_getName(m);
                NSString *selName = NSStringFromSelector(sel);
                if ([selName containsString:@"isActive"] || [selName containsString:@"isPremium"] || [selName containsString:@"current"]) {
                    IMP newImp = imp_implementationWithBlock(^BOOL(id _self) { return YES; });
                    method_setImplementation(m, newImp);
                    qaLog(@"   ✂️ Ép TRUE: %@", selName);
                }
            }
            free(methods);
        }
    }
    free(classes);
}

// --- 3. Bắt Request Mạng ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSString *urlStr = request.URL.absoluteString;
            if ([urlStr containsString:@"verify"] || [urlStr containsString:@"purchase"] || [urlStr containsString:@"premium"]) {
                qaLog(@"🛑 Bắt được API Verify: %@", urlStr);
                NSString *fakeJSON = @"{\"status\":\"success\",\"is_premium\":true,\"active\":true}";
                data = [fakeJSON dataUsingEncoding:NSUTF8StringEncoding];
                response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
            }
        }
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrappedCompletion);
}
%end

// --- 4. Ép Cờ UserDefaults ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    if ([defaultName containsString:@"trialused"] || [defaultName containsString:@"expired"]) return NO;
    if ([defaultName containsString:@"paid"] || [defaultName containsString:@"premium"] || [defaultName containsString:@"pro"]) return YES;
    return %orig;
}
%end

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (StoreKit 2 Bypass)");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        patchStoreKit2();
    });
}
