#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <SystemConfiguration/SystemConfiguration.h>

// 1. Lừa app là đang có mạng (Bypass dòng chữ "Bạn cần kết nối internet")
%hook SCNetworkReachability
- (BOOL)getFlags:(SCNetworkReachabilityFlags *)flags {
    if (flags) {
        *flags = kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsConnectionRequired;
    }
    return YES;
}
%end

// 2. Tự động bấm nút Kích hoạt (An toàn, không đụng vào Label)
%hook UIButton
- (void)layoutSubviews {
    %orig;
    NSString *title = [self titleForState:UIControlStateNormal];
    if ([title containsString:@"Kích hoạt"] || [title containsString:@"Activate"]) {
        // Dùng tag để tránh vòng lặp vô hạn gây crash
        if (self.tag != 9999) {
            self.tag = 9999;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendActionsForControlEvents:UIControlEventTouchUpInside];
                NSLog(@"[QA-MOCK] Auto-clicked Kích hoạt button!");
            });
        }
    }
}
%end

// 3. Giả lập API trả về thành công
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSString *url = request.URL.absoluteString;
    if ([url containsString:@"activate"] || [url containsString:@"license"] || [url containsString:@"tigi"] || [url containsString:@"verify"]) {
        void (^fakeHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSData *mockData = [@"{\"status\":\"success\",\"activated\":true,\"valid\":true,\"code\":200}" dataUsingEncoding:NSUTF8StringEncoding];
            NSHTTPURLResponse *mockResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
            if (completionHandler) completionHandler(mockData, mockResponse, nil);
        };
        completionHandler = fakeHandler;
    }
    return %orig(request, completionHandler);
}
%end

// 4. Đổi nội dung cái popup đòi kích hoạt
%hook UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)preferredStyle {
    if ([title containsString:@"Chưa kích hoạt"] || [message containsString:@"Kích hoạt Filza"]) {
        return %orig(@"Thành công", @"Đã kích hoạt Filza!", UIAlertControllerStyleAlert);
    }
    return %orig;
}
%end

// 5. Đè kết quả JSON (để đảm bảo nếu nó parse JSON thì luôn là true)
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    if (data) {
        NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([str containsString:@"activate"] || [str containsString:@"valid"] || [str containsString:@"success"] || [str containsString:@"false"]) {
            NSData *fakeData = [@"{\"status\":\"success\",\"activated\":true,\"valid\":true,\"success\":true,\"code\":200}" dataUsingEncoding:NSUTF8StringEncoding];
            id result = %orig(fakeData, opt, error);
            if (result) return result;
        }
    }
    return %orig;
}
%end
