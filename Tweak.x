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

// --- 1. Chặn màn hình Paywall (Chỉ chặn, không dùng nil) ---
%hook UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    NSString *clsName = NSStringFromClass([viewControllerToPresent class]).lowercaseString;
    
    if ([clsName containsString:@"trypremium"] || [clsName containsString:@"paywall"]) {
        qaLog(@"🛑 Đã chặn màn hình thanh toán: %@", clsName);
        if (completion) completion();
        return;
    }
    %orig;
}
%end

// --- 2. Hook NSUserDefaults (Chỉ hook boolForKey để tránh crash Firebase) ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"premium"] || [lower containsString:@"pro"] || 
        [lower containsString:@"sub"] || [lower containsString:@"vip"] || 
        [lower containsString:@"plus"] || [lower containsString:@"paid"] ||
        [lower containsString:@"unlocked"]) {
        
        if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
            return NO;
        }
        return YES;
    }
    return %orig;
}
%end

// --- 3. Quét toàn bộ class của App (Bắt trúng Swift) ---
static void patchAppClasses(void) {
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return;

    int hookedCount = 0;
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        NSString *lowerCls = [className lowercaseString];
        
        // Bỏ qua class hệ thống và Firebase (tránh crash)
        if ([className hasPrefix:@"NS"] || [className hasPrefix:@"UI"] || 
            [className hasPrefix:@"SK"] || [className hasPrefix:@"WK"] ||
            [className hasPrefix:@"CA"] || [className hasPrefix:@"CF"] ||
            [className hasPrefix:@"FIR"] || [className hasPrefix:@"GUL"] ||
            [className hasPrefix:@"_NS"] || [className hasPrefix:@"_UI"]) {
            continue;
        }
        
        // Nhắm vào class của Tempmail
        if ([className hasPrefix:@"_TtC"] || [lowerCls containsString:@"tempmail"] || 
            [lowerCls containsString:@"store"] || [lowerCls containsString:@"user"] || 
            [lowerCls containsString:@"premium"] || [lowerCls containsString:@"state"] ||
            [lowerCls containsString:@"manager"]) {
            
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            if (!methods) continue;
            
            for (unsigned int j = 0; j < methodCount; j++) {
                Method method = methods[j];
                SEL selector = method_getName(method);
                NSString *methodName = NSStringFromSelector(selector);
                NSString *lowerMethod = methodName.lowercaseString;
                
                // Quét từ khóa rộng hơn
                if ([lowerMethod containsString:@"premium"] || 
                    [lowerMethod containsString:@"pro"] || 
                    [lowerMethod containsString:@"active"] ||
                    [lowerMethod containsString:@"sub"] ||
                    [lowerMethod containsString:@"purchase"] ||
                    [lowerMethod containsString:@"vip"] ||
                    [lowerMethod containsString:@"plus"] ||
                    [lowerMethod containsString:@"paid"] ||
                    [lowerMethod containsString:@"unlocked"] ||
                    [lowerMethod containsString:@"trial"]) {
                    
                    const char *types = method_getTypeEncoding(method);
                    // Nếu trả về BOOL hoặc Int
                    if (types && (types[0] == 'c' || types[0] == 'B' || types[0] == 'i')) {
                        
                        // Bỏ qua hàm trialUsed để nó đéo báo hết hạn
                        if ([lowerMethod containsString:@"trialused"] || [lowerMethod containsString:@"expired"]) {
                            IMP falseImp = imp_implementationWithBlock(^BOOL(id _self, ...) { return NO; });
                            method_setImplementation(method, falseImp);
                            qaLog(@"✂️ Ép FALSE hàm (Trial): -[%@ %@]", className, methodName);
                        } else {
                            IMP trueImp = imp_implementationWithBlock(^BOOL(id _self, ...) { return YES; });
                            method_setImplementation(method, trueImp);
                            qaLog(@"✂️ Ép TRUE hàm (Pro): -[%@ %@]", className, methodName);
                        }
                        hookedCount++;
                    }
                }
            }
            free(methods);
        }
    }
    free(classes);
    qaLog(@"--- Quét xong. Đã ép %d hàm. ---", hookedCount);
}

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Pro Unlocker)");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        patchAppClasses();
    });
}
