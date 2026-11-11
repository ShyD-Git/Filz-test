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

// --- 1. Đấm Chết Cờ Premium Trong UserDefaults ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"paid_v2_user_enabled"] || 
        [defaultName isEqualToString:@"paid_v2"] || 
        [defaultName isEqualToString:@"paid"]) {
        qaLog(@"✅ Ép TRUE boolForKey: %@", defaultName);
        return YES;
    }
    if ([defaultName containsString:@"trialused"] || [defaultName containsString:@"expired"]) {
        return NO;
    }
    return %orig;
}

- (id)objectForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"paid_v2_user_enabled"]) {
        qaLog(@"✅ Ép @YES objectForKey: %@", defaultName);
        return @YES;
    }
    if ([defaultName isEqualToString:@"paid"] || [defaultName isEqualToString:@"paid_v2"]) {
        return @"602BFAEF-EBF5-478D-878B-FC0149D1BC2E";
    }
    return %orig;
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"paid_v2_user_enabled"]) {
        qaLog(@"🛑 Chặn ghi đè, ép YES: %@", defaultName);
        %orig(YES, defaultName);
        return;
    }
    if ([defaultName containsString:@"trialused"]) {
        %orig(NO, defaultName);
        return;
    }
    %orig;
}
%end

// --- 2. Chặn Cửa Sổ Paywall (Nếu nó cố tình hiện) ---
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

// --- 3. Fake StoreKit 1 (Đề phòng) ---
%hook SKPaymentQueue
- (void)addPayment:(SKPayment *)payment {
    qaLog(@"🛒 Chặn addPayment. Fake mua thành công!");
    
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

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Ultimate UserDefaults Kill)");
}
