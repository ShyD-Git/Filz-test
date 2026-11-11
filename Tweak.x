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

// Hàm đệ quy đập nát JSON, ép mọi cờ thành true
static id modifyJSON(id obj) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dict = [obj mutableCopy];
        for (id key in dict) {
            id val = dict[key];
            NSString *keyStr = [[key description] lowercaseString];
            
            if ([val isKindOfClass:[NSString class]] || [val isKindOfClass:[NSNumber class]]) {
                // Nếu key chứa các từ khóa Premium -> Ép thành true / 1
                if ([keyStr containsString:@"premium"] || [keyStr containsString:@"pro"] || 
                    [keyStr containsString:@"active"] || [keyStr containsString:@"vip"] || 
                    [keyStr containsString:@"paid"] || [keyStr containsString:@"sub"] ||
                    [keyStr containsString:@"tier"] || [keyStr containsString:@"status"]) {
                    
                    if ([val isKindOfClass:[NSNumber class]]) {
                        dict[key] = @(YES);
                    } else {
                        dict[key] = @"true";
                    }
                }
                // Nếu key báo hết hạn -> Ép thành false
                if ([keyStr containsString:@"expired"] || [keyStr containsString:@"trialused"]) {
                    if ([val isKindOfClass:[NSNumber class]]) {
                        dict[key] = @(NO);
                    } else {
                        dict[key] = @"false";
                    }
                }
            } else {
                // Đệ quy nếu là mảng hoặc dict con
                dict[key] = modifyJSON(val);
            }
        }
        return dict;
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *arr = [obj mutableCopy];
        for (NSUInteger i = 0; i < arr.count; i++) {
            arr[i] = modifyJSON(arr[i]);
        }
        return arr;
    }
    return obj;
}

// --- 1. Đớp JSON từ NSJSONSerialization ---
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id obj = %orig;
    if (obj) {
        id modified = modifyJSON(obj);
        if (modified != obj) {
            qaLog(@"📦 Đã sửa JSON NSJSONSerialization");
        }
        return modified;
    }
    return obj;
}
%end

// --- 2. Móc Mạng (Bắt đủ 3 hàm URLSession) ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && request.URL) {
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            qaLog(@"📡 NET 1: %@\nRES: %@", request.URL.absoluteString, str);
        }
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrapped);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && url) {
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            qaLog(@"📡 NET 2: %@\nRES: %@", url.absoluteString, str);
        }
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(url, wrapped);
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    qaLog(@"📡 NET 3: %@", request.URL.absoluteString);
    return %orig;
}
%end

// --- 3. Hook NSUserDefaults (Sửa cờ Local) ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
        return NO;
    }
    if ([lower containsString:@"premium"] || [lower containsString:@"pro"] || 
        [lower containsString:@"active"] || [lower containsString:@"sub"] || 
        [lower containsString:@"vip"] || [lower containsString:@"paid"]) {
        qaLog(@"✅ Ép TRUE Defaults: %@", defaultName);
        return YES;
    }
    return %orig;
}
%end

// --- 4. Chặn Paywall ---
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

// --- 5. Quét Class Swift mò BOOL ---
static void scanClasses() {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        
        if ([className containsString:@"TempMail"] || [className containsString:@"Premium"]) {
            unsigned int mCount;
            Method *methods = class_copyMethodList(cls, &mCount);
            for (unsigned int j = 0; j < mCount; j++) {
                Method m = methods[j];
                SEL sel = method_getName(m);
                NSString *name = NSStringFromSelector(sel).lowercaseString;
                const char *types = method_getTypeEncoding(m);
                
                if (types && (types[0] == 'c' || types[0] == 'B')) {
                    if ([name containsString:@"premium"] || [name containsString:@"pro"] || 
                        [name containsString:@"active"] || [name containsString:@"sub"] || 
                        [name containsString:@"paid"] || [name containsString:@"vip"] ||
                        [name containsString:@"purchase"] || [name containsString:@"trial"]) {
                        
                        IMP newImp = imp_implementationWithBlock(^BOOL(id _self) { return YES; });
                        method_setImplementation(m, newImp);
                        qaLog(@"✂️ Cắt BOOL: %@ %@", className, name);
                    }
                }
            }
            free(methods);
        }
    }
    free(classes);
}

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (JSON Recursive & Network)");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        scanClasses();
    });
}
