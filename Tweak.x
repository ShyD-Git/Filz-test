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

// --- 1. Dump Toàn Bộ UserDefaults ---
%hook NSUserDefaults
- (id)objectForKey:(NSString *)defaultName {
    id obj = %orig;
    // Log cả key và value, bỏ qua mấy key rác của WebKit
    if (![defaultName hasPrefix:@"WebKit"] && ![defaultName hasPrefix:@"NS"]) {
        qaLog(@"🔍 Defaults [%@] = %@", defaultName, obj);
    }
    return obj;
}

- (NSDictionary *)dictionaryRepresentation {
    NSDictionary *dict = %orig;
    qaLog(@"🗂 DUMP TOÀN BỘ USERDEFAULTS: %@", dict);
    return dict;
}
%end

// --- 2. Dump Tất Cả Request Mạng ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (jsonStr.length > 0 && jsonStr.length < 3000) {
                qaLog(@"📡 URL: %@\nBODY: %@", request.URL.absoluteString, jsonStr);
            }
        }
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrappedCompletion);
}
%end

// --- 3. Dump Method List Của Class API ---
static void dumpClassMethods(const char *className) {
    Class cls = objc_getClass(className);
    if (!cls) {
        qaLog(@"❌ Không tìm thấy class: %s", className);
        return;
    }
    
    qaLog(@"🔍 Methods của %s:", className);
    unsigned int count;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        Method m = methods[i];
        SEL sel = method_getName(m);
        qaLog(@"   -> %s", sel_getName(sel));
    }
    free(methods);
}

%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:qaLogPath() error:nil];
    qaLog(@"🚀 QATestingUtils Loaded (Deep Inspector)");
    
    // Đợi app load xong class rồi mới dump
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dumpClassMethods("TempMailPremiumAPI.UserSessionResultClass");
        dumpClassMethods("TempMailPremiumAPI.UserSessionResponseParser");
        dumpClassMethods("TempMailPremiumAPI.TempMailPremiumAPIService");
        dumpClassMethods("TempMail.PurchaseCoordinator");
    });
}
