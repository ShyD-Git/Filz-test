#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// Khai báo Interface đầy đủ (Xóa mọi dòng @class nếu có)
@interface TGUserDefaults : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isActivated;
- (void)setIsActivated:(BOOL)activated;
- (void)setLicenseType:(NSString *)type;
- (void)setBool:(BOOL)arg1 forKey:(id)arg2;
- (void)setObject:(id)arg1 forKey:(id)arg2;
- (id)objectForKey:(id)arg1;
- (void)synchronize;
@end

// Hàm ghi log ra file
static void logToFile(NSString *msg) {
    NSString *path = @"/var/mobile/Library/Preferences/filza_hook.log";
    NSString *log = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [log writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
        [file seekToEndOfFile];
        [file writeData:[log dataUsingEncoding:NSUTF8StringEncoding]];
        [file closeFile];
    }
}

// 1. Hook TGUserDefaults (Ép kích hoạt)
%hook TGUserDefaults
- (BOOL)isActivated {
    return YES;
}
- (BOOL)boolForKey:(NSString *)key {
    NSString *lower = [key lowercaseString];
    if ([lower containsString:@"activ"] || [lower containsString:@"licens"] || [lower containsString:@"trial"]) {
        return YES;
    }
    return %orig;
}
- (id)objectForKey:(NSString *)key {
    NSString *lower = [key lowercaseString];
    if ([lower containsString:@"licens"] || [lower containsString:@"status"]) {
        return @"Lifetime";
    }
    return %orig;
}
- (void)synchronize {
    [self setBool:YES forKey:@"is_activated"];
    [self setObject:@"Lifetime" forKey:@"license_status"];
    %orig;
}
%end

// 2. Hook UIViewController để log màn hình
%hook UIViewController
- (void)viewDidLoad {
    %orig;
    logToFile([NSString stringWithFormat:@"[VIEW LOADED] %@", NSStringFromClass([self class])]);
}
%end

// 3. Theo dõi nút Kích hoạt
%hook UIButton
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    logToFile([NSString stringWithFormat:@"[BUTTON TAPPED] %@ -> %@", [self titleForState:UIControlStateNormal], NSStringFromSelector(action)]);
    %orig;
}
- (void)layoutSubviews {
    %orig;
    NSString *title = [self titleForState:UIControlStateNormal];
    if ([title containsString:@"Kích hoạt"] || [title containsString:@"Activate"]) {
        if (self.tag != 9999) {
            self.tag = 9999;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendActionsForControlEvents:UIControlEventTouchUpInside];
            });
        }
    }
}
%end

// 4. Quét class để tìm hàm ẩn
%ctor {
    logToFile(@"=== APP STARTED ===");
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    objc_getClassList(classes, numClasses);

    for (int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        
        if ([className hasPrefix:@"TG"] || [className containsString:@"Licens"] || [className containsString:@"Activ"]) {
            unsigned int methodCount;
            Method *methods = class_copyMethodList(cls, &methodCount);
            for (unsigned int j = 0; j < methodCount; j++) {
                NSString *methodName = NSStringFromSelector(method_getName(methods[j]));
                NSString *lower = [methodName lowercaseString];
                
                if ([lower containsString:@"activ"] || [lower containsString:@"licens"] || [lower containsString:@"serial"] || [lower containsString:@"status"]) {
                    logToFile([NSString stringWithFormat:@"[FOUND METHOD] %@ - %@", className, methodName]);
                }
            }
            free(methods);
        }
    }
    free(classes);
}
