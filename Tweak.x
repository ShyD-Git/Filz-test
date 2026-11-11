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

// --- 1. Bắt trọn mạng để xem cấu trúc JSON ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (jsonStr.length > 0 && jsonStr.length < 2000) {
                // Dump mọi thứ, đéo cần biết URL là gì
                qaLog(@"📡 URL: %@\nBODY: %@", request.URL.absoluteString, jsonStr);
                
                @try {
                    NSMutableString *mutStr = [jsonStr mutableCopy];
                    // Quét sạch cờ false liên quan đến premium
                    [mutStr replaceOccurrencesOfString:@"\"premium\":false" withString:@"\"premium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"is_premium\":false" withString:@"\"is_premium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"isPremium\":false" withString:@"\"isPremium\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"active\":false" withString:@"\"active\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"isActive\":false" withString:@"\"isActive\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    [mutStr replaceOccurrencesOfString:@"\"subscribed\":false" withString:@"\"subscribed\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                    
                    if (![mutStr isEqualToString:jsonStr]) {
                        data = [mutStr dataUsingEncoding:NSUTF8StringEncoding];
                    }
                } @catch (NSException *e) {}
            }
        }
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrappedCompletion);
}
%end

// --- 2. Vá chết hàm Swift (PurchaseCoordinator) ---
static void patchSwiftMethods(void) {
    NSArray *targetClasses = @[
        @"TempMail.PurchaseCoordinator",
        @"TempMailPremiumAPI.UserSessionResultClass",
        @"TempMailPremiumAPI.UserSessionResponseParser"
    ];
    
    for (NSString *clsName in targetClasses) {
        Class cls = objc_getClass([clsName UTF8String]);
        if (!cls) continue;
        
        unsigned int count;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            Method m = methods[i];
            SEL sel = method_getName(m);
            NSString *selName = NSStringFromSelector(sel);
            
            qaLog(@"🔍 Tìm thấy hàm: %@ trong %@", selName, clsName);
            
            // Đớp mọi hàm có chữ purchase, restore, active, premium
            if ([selName.lowercaseString containsString:@"purchase"] || 
                [selName.lowercaseString containsString:@"restore"] ||
                [selName.lowercaseString containsString:@"active"] ||
                [selName.lowercaseString containsString:@"premium"]) {
                
                IMP newImp = imp_implementationWithBlock(^(id _self, ...) {
                    qaLog(@"🛑 Đã chặn hàm: %@", selName);
                    // Ép trả về YES nếu là hàm bool
                    return YES; 
                });
                method_setImplementation(m, newImp);
            }
        }
        free(methods);
    }
}

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Full Dump & Swift Patch)");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        patchSwiftMethods();
    });
}
