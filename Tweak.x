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

// --- 1. Sửa Logic Ép Bool (Trial = NO, Premium = YES) ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    
    // 1. Phải check trial/expired TRƯỚC ĐỂ NÓ TRẢ VỀ FALSE
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
        qaLog(@"✅ Ép FALSE (Trial): %@", defaultName);
        return NO;
    }
    
    // 2. Ép các cờ Premium
    if ([lower containsString:@"paid"] || 
        [lower containsString:@"premium"] || 
        [lower containsString:@"enabled"] || 
        [lower containsString:@"pro"]) {
        qaLog(@"✅ Ép TRUE (Premium): %@", defaultName);
        return YES;
    }
    
    return %orig;
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName {
    NSString *lower = defaultName.lowercaseString;
    
    if ([lower containsString:@"trialused"] || [lower containsString:@"expired"]) {
        %orig(NO, defaultName);
        return;
    }
    
    if ([lower containsString:@"paid"] || 
        [lower containsString:@"premium"] || 
        [lower containsString:@"enabled"] || 
        [lower containsString:@"pro"]) {
        %orig(YES, defaultName);
        return;
    }
    
    %orig;
}
%end

// --- 2. Fake StoreKit 1 (Dự phòng) ---
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
    qaLog(@"🚀 QATestingUtils Loaded (Fixed Logic)");
}
