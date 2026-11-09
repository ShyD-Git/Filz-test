#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// Hàm tự động kích hoạt ngầm
static void forceActivateApp() {
    Class TGUserDefaults = objc_getClass("TGUserDefaults");
    if (TGUserDefaults) {
        id sharedInstance = ((id (*)(id, SEL))objc_msgSend)((id)TGUserDefaults, sel_registerName("sharedInstance"));
        if (sharedInstance) {
            // Ghi đè trạng thái vào bộ nhớ đệm
            ((void (*)(id, SEL, BOOL))objc_msgSend)(sharedInstance, sel_registerName("setIsActivated:"), YES);
            ((void (*)(id, SEL, id))objc_msgSend)(sharedInstance, sel_registerName("setLicenseType:"), @"Lifetime");
            ((void (*)(id, SEL, id))objc_msgSend)(sharedInstance, sel_registerName("setObject:forKey:"), @"Lifetime", @"license_status");
            ((void (*)(id, SEL))objc_msgSend)(sharedInstance, sel_registerName("synchronize"));
        }
    }
}

// 1. Hook cứng class quản lý bộ nhớ của Filza
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
    // Trước khi lưu file, ép nó ghi trạng thái Vĩnh viễn
    [self setBool:YES forKey:@"is_activated"];
    [self setObject:@"Lifetime" forKey:@"license_status"];
    %orig;
}
%end

// 2. Chặn mạng
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSString *url = request.URL.absoluteString;
    if ([url containsString:@"activate"] || [url containsString:@"license"] || [url containsString:@"tigi"] || [url containsString:@"verify"]) {
        void (^fakeHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSData *mockData = [@"{\"status\":\"success\",\"activated\":true,\"valid\":true,\"license\":\"Lifetime\",\"code\":200}" dataUsingEncoding:NSUTF8StringEncoding];
            NSHTTPURLResponse *mockResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
            if (completionHandler) completionHandler(mockData, mockResponse, nil);
        };
        completionHandler = fakeHandler;
    }
    return %orig(request, completionHandler);
}
%end

// 3. Đè kết quả JSON
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    if (data) {
        NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([str containsString:@"activate"] || [str containsString:@"valid"] || [str containsString:@"success"] || [str containsString:@"false"]) {
            NSData *fakeData = [@"{\"status\":\"success\",\"activated\":true,\"valid\":true,\"license\":\"Lifetime\",\"success\":true,\"code\":200}" dataUsingEncoding:NSUTF8StringEncoding];
            id result = %orig(fakeData, opt, error);
            if (result) return result;
        }
    }
    return %orig;
}
%end

// 4. Đổi chữ hiển thị
%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    for (UIView *view in self.contentView.subviews) {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)view;
            if ([lbl.text containsString:@"DÙNG THỬ"] || [lbl.text containsString:@"Dùng thử"] || [lbl.text containsString:@"Chưa kích hoạt"]) {
                lbl.text = @"VĨNH VIỄN";
                lbl.textColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0];
            }
        }
    }
}
%end

// 5. Tự động kích hoạt ngay khi app vừa load xong
%ctor {
    forceActivateApp();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        forceActivateApp();
    }];
}
