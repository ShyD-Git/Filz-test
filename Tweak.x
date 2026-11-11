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

// --- 1. Múc JSON trả về từ API (Ép cờ Premium) ---
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id obj = %orig;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dict = [obj mutableCopy];
        BOOL changed = NO;
        
        // Quét các key phổ biến của app Premium
        NSArray *keys = @[@"premium", @"is_premium", @"isPremium", @"active", @"isActive", @"subscription", @"isSubscribed", @"trial", @"isTrial"];
        
        for (NSString *key in keys) {
            if (dict[key] != nil) {
                dict[key] = @YES;
                changed = YES;
            }
        }
        
        if (changed) {
            qaLog(@"📦 Đã can thiệp JSON API: %@", dict);
            return dict;
        }
    }
    return obj;
}
%end

// --- 2. Hook NSUserDefaults (Cờ Trial & Premium local) ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"] || [lower containsString:@"wasused"]) {
        qaLog(@"✅ Ép FALSE Defaults: %@", defaultName);
        return NO;
    }
    if ([lower containsString:@"premium"] || [lower containsString:@"pro"] || 
        [lower containsString:@"sub"] || [lower containsString:@"vip"] || 
        [lower containsString:@"paid"] || [lower containsString:@"unlocked"] ||
        [lower containsString:@"active"]) {
        qaLog(@"✅ Ép TRUE Defaults: %@", defaultName);
        return YES;
    }
    return %orig;
}
%end

// --- 3. Chặn bảng thanh toán ---
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

// --- 4. Dump Thuộc tính của Class Lõi (Xem nó giấu cờ ở đâu) ---
static void dumpProperties() {
    NSArray *classesToDump = @[
        @"TempMailPremiumAPI.UserSessionResultClass",
        @"TempMailPremiumAPI.UserSessionResponseParser",
        @"TempMail.ApplicationCoordinator"
    ];
    
    for (NSString *clsName in classesToDump) {
        Class cls = objc_getClass([clsName UTF8String]);
        if (!cls) continue;
        
        qaLog(@"🔍 Dump Properties của %@:", clsName);
        unsigned int count;
        objc_property_t *props = class_copyPropertyList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            qaLog(@"   🔑 Property: %s", property_getName(props[i]));
        }
        free(props);
    }
}

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (JSON Interceptor)");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dumpProperties();
    });
}
