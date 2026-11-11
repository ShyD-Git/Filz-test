#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Đổi sang thư mục tmp của app để bypass sandbox
static NSString *qaLogPath() {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"QATestingUtils.log"];
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
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:qaLogPath()];
        if (fileHandle == nil) {
            [line writeToFile:qaLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fileHandle closeFile];
        }
    });
}

// --- 1. Bắt màn hình Paywall và đá văng ---
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *clsName = NSStringFromClass([self class]);
    
    // Bắt các class có tên chứa Paywall hoặc Premium
    if ([clsName.lowercaseString containsString:@"paywall"] || 
        [clsName.lowercaseString containsString:@"premium"] ||
        [clsName.lowercaseString containsString:@"upgrade"]) {
        
        qaLog(@"🛑 Đá văng màn hình: %@", clsName);
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}
%end

// --- 2. Hook StoreKit 2 (Transaction) ---
// StoreKit 2 dùng class Swift, tao hook các hàm ObjC cầu nối
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    if ([lower containsString:@"premium"] || [lower containsString:@"pro"] || 
        [lower containsString:@"sub"] || [lower containsString:@"purchase"]) {
        qaLog(@"✅ Ép True NSUserDefaults: %@", defaultName);
        return YES;
    }
    return %orig;
}
%end

// --- 3. Quét toàn bộ class Swift ra log để tìm mục tiêu ---
static void dumpClassesToLog(void) {
    qaLog(@"--- BẮT ĐẦU QUÉT CLASS ---");
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    
    NSArray *keywords = @[@"paywall", @"premium", @"store", @"purchase", @"sub", @"iap", @"pro", @"user"];
    
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        NSString *lowerName = className.lowercaseString;
        
        BOOL match = NO;
        for (NSString *kw in keywords) {
            if ([lowerName containsString:kw]) { match = YES; break; }
        }
        
        if (match) {
            qaLog(@"Class: %@", className);
            
            // Dump các hàm có khả năng trả về BOOL
            unsigned int mCount;
            Method *methods = class_copyMethodList(cls, &mCount);
            for (unsigned int j = 0; j < mCount; j++) {
                SEL sel = method_getName(methods[j]);
                NSString *selName = NSStringFromSelector(sel);
                const char *types = method_getTypeEncoding(methods[j]);
                
                if (types && (types[0] == 'c' || types[0] == 'B')) {
                    qaLog(@"   -> Method (BOOL): %@", selName);
                    
                    // Thử vá luôn hàm đó nếu có chữ pro/premium
                    if ([selName.lowercaseString containsString:@"pro"] || 
                        [selName.lowercaseString containsString:@"premium"] || 
                        [selName.lowercaseString containsString:@"active"]) {
                        
                        IMP newImp = imp_implementationWithBlock(^BOOL(id _self, ...) { return YES; });
                        method_setImplementation(methods[j], newImp);
                        qaLog(@"   ✂️ Đã vá ép TRUE: %@", selName);
                    }
                }
            }
            free(methods);
        }
    }
    free(classes);
    qaLog(@"--- QUÉT CLASS XONG ---");
}

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    
    qaLog(@"=======================");
    qaLog(@"🚀 QATestingUtils Loaded!");
    qaLog(@"=======================");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dumpClassesToLog();
    });
}
