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

// --- 1. Log mọi key UserDefaults mà app đọc để tìm cờ Pro ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    BOOL orig = %orig;
    qaLog(@"🔍 Đọc Defaults [%@] = %d", defaultName, orig);
    
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"premium"] || [lower containsString:@"pro"] || 
        [lower containsString:@"sub"] || [lower containsString:@"vip"] || 
        [lower containsString:@"paid"] || [lower containsString:@"unlocked"] ||
        [lower containsString:@"active"]) {
        
        qaLog(@"✅ Ép TRUE Defaults: %@", defaultName);
        return YES;
    }
    return orig;
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

// --- 3. Chỉ quét class của app Tempmail (Bỏ qua Apple/Google) ---
static void patchAppClasses(void) {
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return;

    int hookedCount = 0;
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        NSString *lowerCls = [className lowercaseString];
        
        // CHỈ NHẮM VÀO CLASS CỦA APP (Tempmail / TempMail)
        if ([lowerCls containsString:@"tempmail"] || [lowerCls containsString:@"applicationcoordinator"]) {
            
            qaLog(@"🎯 Tìm thấy class App: %@", className);
            
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            if (!methods) continue;
            
            for (unsigned int j = 0; j < methodCount; j++) {
                Method method = methods[j];
                SEL selector = method_getName(method);
                NSString *methodName = NSStringFromSelector(selector);
                NSString *lowerMethod = methodName.lowercaseString;
                
                // Quét các hàm check quyền
                if ([lowerMethod containsString:@"premium"] || 
                    [lowerMethod containsString:@"pro"] || 
                    [lowerMethod containsString:@"active"] ||
                    [lowerMethod containsString:@"sub"] ||
                    [lowerMethod containsString:@"vip"] ||
                    [lowerMethod containsString:@"paid"] ||
                    [lowerMethod containsString:@"trial"]) {
                    
                    const char *types = method_getTypeEncoding(method);
                    if (types && (types[0] == 'c' || types[0] == 'B' || types[0] == 'i')) {
                        
                        if ([lowerMethod containsString:@"trialused"] || [lowerMethod containsString:@"expired"]) {
                            IMP falseImp = imp_implementationWithBlock(^BOOL(id _self, ...) { return NO; });
                            method_setImplementation(method, falseImp);
                            qaLog(@"✂️ Ép FALSE: -[%@ %@]", className, methodName);
                        } else {
                            IMP trueImp = imp_implementationWithBlock(^BOOL(id _self, ...) { return YES; });
                            method_setImplementation(method, trueImp);
                            qaLog(@"✂️ Ép TRUE: -[%@ %@]", className, methodName);
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
    qaLog(@"🚀 QATestingUtils Loaded (Targeted)");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        patchAppClasses();
    });
}
