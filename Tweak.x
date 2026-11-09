#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

@interface TGUserDefaults : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isActivated;
- (void)setIsActivated:(BOOL)activated;
- (void)setLicenseType:(NSString *)type;
- (void)setBool:(BOOL)arg1 forKey:(id)arg2;
- (void)setObject:(id)arg1 forKey:(id)arg2;
- (id)objectForKey:(id)arg1;
@end

// 1. Hook cứng class quản lý bộ nhớ (Bỏ synchronize để đéo bị crash)
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
%end

// 2. Chặn mạng, giả lập kích hoạt thành công
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

// 5. Tự động bấm nút Kích hoạt (nếu có)
%hook UIButton
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
