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

// --- 1. Chặn ghi đè Premium vào UserDefaults ---
%hook NSUserDefaults
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    
    if ([lower containsString:@"premium"] || [lower containsString:@"pro"] || 
        [lower containsString:@"active"] || [lower containsString:@"sub"] || 
        [lower containsString:@"vip"] || [lower containsString:@"paid"] ||
        [lower containsString:@"unlocked"]) {
        qaLog(@"🛑 Chặn setBool: %@ -> Ép YES", defaultName);
        %orig(YES, defaultName);
        return;
    }
    
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
        qaLog(@"🛑 Chặn setBool: %@ -> Ép NO", defaultName);
        %orig(NO, defaultName);
        return;
    }
    %orig;
}
%end

// --- 2. Fake StoreKit 1 (Giao dịch mua thành công) ---
%hook SKPaymentQueue
- (void)addPayment:(SKPayment *)payment {
    qaLog(@"🛒 Chặn addPayment. Giả lập mua thành công!");
    
    SKPaymentTransaction *transaction = [[objc_getClass("SKPaymentTransaction") alloc] init];
    [transaction setValue:payment forKey:@"payment"];
    [transaction setValue:@(SKPaymentTransactionStatePurchased) forKey:@"transactionState"];
    [transaction setValue:[NSUUID UUID] forKey:@"transactionIdentifier"];
    [transaction setValue:[NSDate date] forKey:@"transactionDate"];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (id observer in [[SKPaymentQueue defaultQueue] valueForKey:@"_observers"]) {
            if ([observer respondsToSelector:@selector(paymentQueue:updatedTransactions:)]) {
                [observer paymentQueue:[SKPaymentQueue defaultQueue] updatedTransactions:@[transaction]];
            }
        }
    });
}
%end

// --- 3. Bắt Mạng (Sửa JSON trả về) ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && request.URL) {
            NSString *urlStr = request.URL.absoluteString;
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            
            if ([urlStr containsString:@"session"] || [urlStr containsString:@"user"] || 
                [urlStr containsString:@"premium"] || [urlStr containsString:@"activate"] || 
                [urlStr containsString:@"receipt"] || [urlStr containsString:@"verify"] ||
                [urlStr containsString:@"mailbox"]) {
                
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
                        [mutStr replaceOccurrencesOfString:@"\"is_pro\":false" withString:@"\"is_pro\":true" options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutStr.length)];
                        
                        if (![mutStr isEqualToString:jsonStr]) {
                            qaLog(@"✂️ Đã đổi cờ Premium thành TRUE trong response");
                            data = [mutStr dataUsingEncoding:NSUTF8StringEncoding];
                        }
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

// --- 4. Hook Swift Class bằng Runtime API (Không dùng %hook) ---
static void patchSwiftClasses(void) {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        
        // Nhắm vào các class Swift của TempMail có chứa chữ Purchase hoặc Premium
        if ([className containsString:@"TempMail"] && 
           ([className containsString:@"Purchase"] || [className containsString:@"Premium"])) {
            
            qaLog(@"🎯 Quét class Swift: %@", className);
            unsigned int methodCount;
            Method *methods = class_copyMethodList(cls, &methodCount);
            
            for (unsigned int j = 0; j < methodCount; j++) {
                Method method = methods[j];
                SEL selector = method_getName(method);
                NSString *methodName = NSStringFromSelector(selector);
                
                if ([methodName containsString:@"purchase"] || [methodName containsString:@"restore"]) {
                    qaLog(@"   ✂️ Hook hàm Swift: %@", methodName);
                    
                    // Thay thế hàm bằng một block rỗng để chặn giao dịch thật
                    IMP newImp = imp_implementationWithBlock(^(id _self, ...) {
                        qaLog(@"   🛑 Đã chặn hàm Swift: %@", methodName);
                    });
                    method_setImplementation(method, newImp);
                }
            }
            free(methods);
        }
    }
    free(classes);
}

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Swift Runtime Hook)");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        patchSwiftClasses();
    });
}
