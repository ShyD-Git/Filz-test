#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// Lớp 1: Đè bộ nhớ đệm
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = [defaultName lowercaseString];
    if ([lower containsString:@"activat"] || [lower containsString:@"licens"] || [lower containsString:@"valid"] || [lower containsString:@"tigi"] || [lower containsString:@"purchas"]) {
        return YES;
    }
    return %orig;
}
- (id)objectForKey:(NSString *)defaultName {
    NSString *lower = [defaultName lowercaseString];
    if ([lower containsString:@"activat"] || [lower containsString:@"licens"] || [lower containsString:@"valid"] || [lower containsString:@"tigi"] || [lower containsString:@"purchas"]) {
        return @YES;
    }
    return %orig;
}
%end

// Lớp 2: Chặn API mạng
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSString *url = request.URL.absoluteString;
    if ([url containsString:@"activate"] || [url containsString:@"license"] || [url containsString:@"tigi"]) {
        void (^fakeHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSData *mockData = [@"{\"status\":\"success\",\"activated\":true,\"valid\":true,\"code\":200}" dataUsingEncoding:NSUTF8StringEncoding];
            if (completionHandler) completionHandler(mockData, response, nil);
        };
        completionHandler = fakeHandler;
    }
    return %orig(request, completionHandler);
}
%end

// Lớp 3: Đè kết quả JSON
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

// Lớp 4: Bắt Alert "Chưa kích hoạt" từ trong trứng nước, gọi ngầm và chặn hiển thị
%hook UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    if ([viewControllerToPresent isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewControllerToPresent;
        if ([alert.title containsString:@"Chưa kích hoạt"] || [alert.message containsString:@"Kích hoạt Filza"]) {
            
            // Lưu trạng thái
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"is_activated"];
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"activated"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            // Tự động trigger nút Kích hoạt (gọi handler ngầm)
            for (UIAlertAction *action in alert.actions) {
                if ([action.title containsString:@"Kích hoạt"]) {
                    void (^handler)(UIAlertAction *) = [action valueForKey:@"handler"];
                    if (handler) {
                        handler(action);
                    }
                    break;
                }
            }
            
            // Chặn đéo cho cái popup hiện ra
            NSLog(@"[QA-MOCK] Đã chặn popup kích hoạt!");
            return; 
        }
    }
    %orig;
}
%end

// Lớp 5: Đổi text đỏ thành xanh (Bỏ hoàn toàn block dispatch_after gây crash)
%hook UILabel
- (void)setText:(NSString *)text {
    if ([text containsString:@"Thất bại"] || [text containsString:@"Không thể kích hoạt"] || [text containsString:@"Failed"]) {
        %orig(@"Thành công. Đã kích hoạt Filza!");
        return;
    }
    %orig;
}
%end
