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

// --- 1. Chặn đứng Paywall ngay từ lúc gọi hàm Present ---
%hook UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    NSString *clsName = NSStringFromClass([viewControllerToPresent class]).lowercaseString;
    
    // Bắt tên class có chữ paywall, premium, purchase, store
    if ([clsName containsString:@"paywall"] || 
        [clsName containsString:@"premium"] || 
        [clsName containsString:@"purchase"] ||
        [clsName containsString:@"store"]) {
        
        qaLog(@"🛑 Chặn đứng Paywall: %@", clsName);
        if (completion) completion();
        return; // Đéo gọi %orig, màn hình đéo hiện
    }
    %orig;
}
%end

// --- 2. Hook StoreKit 2 / NSUserDefaults (Ép cờ Pro) ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"premium"] || [lower containsString:@"pro"] || 
        [lower containsString:@"sub"] || [lower containsString:@"active"] || 
        [lower containsString:@"trial"]) {
        qaLog(@"✅ Ép NSUserDefaults [%@] = YES", defaultName);
        return YES;
    }
    return %orig;
}
%end

// --- 3. Quét hàm Bool (Chỉ quét app, bỏ qua hệ thống) ---
static void scanSwiftMethods(void) {
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return;

    int hookedCount = 0;
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        
        // Class của app Swift thường bắt đầu bằng _TtC hoặc chứa chữ Manager, Store, User
        if ([className hasPrefix:@"_TtC"] || 
            [className.lowercaseString containsString:@"store"] || 
            [className.lowercaseString containsString:@"user"] ||
            [className.lowercaseString containsString:@"purchase"]) {
            
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            if (!methods) continue;
            
            for (unsigned int j = 0; j < methodCount; j++) {
                Method method = methods[j];
                SEL selector = method_getName(method);
                NSString *methodName = NSStringFromSelector(selector);
                NSString *lowerMethod = methodName.lowercaseString;
                
                if ([lowerMethod containsString:@"premium"] || 
                    [lowerMethod containsString:@"pro"] || 
                    [lowerMethod containsString:@"active"] ||
                    [lowerMethod containsString:@"sub"] ||
                    [lowerMethod containsString:@"trial"]) {
                    
                    const char *types = method_getTypeEncoding(method);
                    if (types && (types[0] == 'c' || types[0] == 'B' || types[0] == 'i')) { // BOOL hoặc Int
                        IMP newImp = imp_implementationWithBlock(^BOOL(id _self, ...) {
                            return YES;
                        });
                        method_setImplementation(method, newImp);
                        qaLog(@"✂️ Ép TRUE hàm: -[%@ %@]", className, methodName);
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
    // Xóa log cũ
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    
    qaLog(@"=======================");
    qaLog(@"🚀 QATestingUtils Loaded!");
    qaLog(@"=======================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        qaLog(@"Bắt đầu quét class...");
        scanSwiftMethods();
    });
}
