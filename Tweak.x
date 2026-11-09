#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// Lớp 1: Đè toàn bộ kết quả đọc từ bộ nhớ đệm (NSUserDefaults)
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

// Lớp 4: TỰ ĐỘNG BẤM NÚT KÍCH HOẠT
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    // Quét tìm nút "Kích hoạt" và tự động bấm
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self scanAndClickActivate:self.view];
    });
}

- (void)scanAndClickActivate:(UIView *)view {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)subview;
            NSString *title = [btn titleForState:UIControlStateNormal];
            
            if ([title containsString:@"Kích hoạt"] || [title containsString:@"Activate"]) {
                [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                NSLog(@"[QA-MOCK] Tự động bấm nút Kích hoạt!");
            }
        }
        [self scanAndClickActivate:subview]; // Đệ quy tìm tiếp
    }
}
%end

// Lớp 5: Đổi text đỏ thành xanh và tự động đóng popup
%hook UILabel
- (void)setText:(NSString *)text {
    if ([text containsString:@"Thất bại"] || [text containsString:@"Không thể kích hoạt"] || [text containsString:@"Failed"]) {
        %orig(@"Thành công. Đã kích hoạt Filza!");
        
        // Lưu cứng trạng thái vào bộ nhớ
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"is_activated"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"activated"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        // Tự động đóng popup
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = nil;
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                            if (w.isKeyWindow) { keyWindow = w; break; }
                        }
                    }
                }
            } else {
                keyWindow = [UIApplication sharedApplication].keyWindow;
            }
            UIViewController *rootVC = keyWindow.rootViewController;
            if (rootVC.presentedViewController) {
                [rootVC dismissViewControllerAnimated:YES completion:nil];
            }
        });
        return;
    }
    %orig;
}
%end
