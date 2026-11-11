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

// --- 1. Hook NSUserDefaults (Sửa cờ Trial) ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    
    // Ép các cờ Trial / Expired thành NO để nó tưởng chưa dùng
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"] || [lower containsString:@"wasused"]) {
        qaLog(@"✅ Ép FALSE Defaults (Trial): %@", defaultName);
        return NO;
    }
    
    // Ép các cờ Premium thành YES
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

// --- 2. Chặn màn hình thanh toán ---
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

// --- 3. Chọc thẳng vào các class lõi của App ---
static void patchAppClasses(void) {
    NSArray *classesToPatch = @[
        @"TempMailPremiumAPI.UserSessionResultClass",
        @"TempMailPremiumAPI.UserSessionResponseParser",
        @"TempMailPremiumAPI.APIPremiumServiceUtils",
        @"TempMailPremiumAPI.TempMailPremiumAPIService",
        @"TempMail.ApplicationCoordinator",
        @"TempMailPremiumAPI.APIUserSessionRequest",
        @"TempMailPremiumAPI.APIUserActivationRequestV2",
        @"TempMailPremiumAPI.APIUserActivationRequest",
        @"TempMailPremiumAPI.APIPremiumRequest",
        @"TempMail.DataCoordinator"
    ];
    
    for (NSString *clsName in classesToPatch) {
        Class cls = objc_getClass([clsName UTF8String]);
        if (!cls) {
            qaLog(@"❌ Không tìm thấy class: %@", clsName);
            continue;
        }
        
        qaLog(@"🎯 Đang mổ class: %@", clsName);
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (!methods) continue;
        
        for (unsigned int j = 0; j < methodCount; j++) {
            Method method = methods[j];
            SEL selector = method_getName(method);
            NSString *methodName = NSStringFromSelector(selector);
            const char *types = method_getTypeEncoding(method);
            
            // Hook tất cả hàm trả về BOOL hoặc Int
            if (types && (types[0] == 'c' || types[0] == 'B' || types[0] == 'i')) {
                IMP newImp = imp_implementationWithBlock(^BOOL(id _self, ...) {
                    return YES;
                });
                method_setImplementation(method, newImp);
                qaLog(@"   ✂️ Ép TRUE: %@", methodName);
            }
        }
        free(methods);
    }
}

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Hardcore Pro)");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        patchAppClasses();
    });
}
