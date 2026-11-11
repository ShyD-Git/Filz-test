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

// --- 1. Giết Popup chặn tính năng ---
%hook UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)preferredStyle {
    if ([title containsString:@"Cao cấp"] || [title containsString:@"Premium"] || 
        [message containsString:@"Cao cấp"] || [message containsString:@"nâng cấp"]) {
        qaLog(@"🛑 Đã bóp mồm Popup: %@", title);
        return nil; // Đéo cho phép hiện popup
    }
    return %orig;
}
%end

// --- 2. Ép cờ Pro trong NSUserDefaults ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"premium"] || [lower containsString:@"pro"] || 
        [lower containsString:@"sub"] || [lower containsString:@"trial"] || 
        [lower containsString:@"ad"]) {
        
        // Trial đã dùng thì ép thành NO để nó đéo bắt mua nữa, còn lại ép YES
        if ([lower containsString:@"trialused"]) {
            return NO; 
        }
        return YES;
    }
    return %orig;
}
%end

// --- 3. Quét và tiêu diệt class của App (Tempmail) ---
static void patchAppClasses(void) {
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return;

    int hookedCount = 0;
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        
        // Chỉ nhắm vào class của Tempmail (Swift thường có tên _TtC8tempmail...)
        if ([className containsString:@"tempmail"] || [className containsString:@"ApplicationCoordinator"]) {
            
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            if (!methods) continue;
            
            for (unsigned int j = 0; j < methodCount; j++) {
                Method method = methods[j];
                SEL selector = method_getName(method);
                NSString *methodName = NSStringFromSelector(selector);
                NSString *lowerMethod = methodName.lowercaseString;
                
                // Đớp mọi hàm check quyền lợi
                if ([lowerMethod containsString:@"premium"] || 
                    [lowerMethod containsString:@"pro"] || 
                    [lowerMethod containsString:@"sub"] ||
                    [lowerMethod containsString:@"purchase"] ||
                    [lowerMethod containsString:@"active"] ||
                    [lowerMethod containsString:@"ad"]) {
                    
                    const char *types = method_getTypeEncoding(method);
                    // Nếu trả về BOOL hoặc Int
                    if (types && (types[0] == 'c' || types[0] == 'B' || types[0] == 'i')) {
                        IMP newImp = imp_implementationWithBlock(^BOOL(id _self, ...) {
                            return YES; // Ép mọi thứ thành TRUE
                        });
                        method_setImplementation(method, newImp);
                        qaLog(@"✂️ Cắt tiết hàm: -[%@ %@]", className, methodName);
                        hookedCount++;
                    }
                }
            }
            free(methods);
        }
    }
    free(classes);
    qaLog(@"--- Xong. Đã cắt %d hàm của app ---", hookedCount);
}

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Premium Injector)");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        patchAppClasses();
    });
}
