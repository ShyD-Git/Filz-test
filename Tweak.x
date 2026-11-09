#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// Hàm C đệ quy quét mọi ngóc ngách của UIView
static void scanAndClickButton(UIView *view) {
    if (!view) return;
    for (UIView *subview in view.subviews) {
        // 1. Nếu là UIButton
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)subview;
            NSString *title = [btn titleForState:UIControlStateNormal];
            if ([title containsString:@"Kích hoạt"] || [title containsString:@"Activate"]) {
                [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                NSLog(@"[QA-MOCK] Đã tự động bấm nút Kích hoạt!");
                return;
            }
        } 
        // 2. Nếu là UILabel nằm trong một UIControl (nút custom)
        else if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)subview;
            if ([lbl.text containsString:@"Kích hoạt"] || [lbl.text containsString:@"Activate"]) {
                UIView *parent = lbl.superview;
                while (parent) {
                    if ([parent isKindOfClass:[UIControl class]]) {
                        [(UIControl *)parent sendActionsForControlEvents:UIControlEventTouchUpInside];
                        NSLog(@"[QA-MOCK] Đã tự động bấm qua UILabel!");
                        return;
                    }
                    parent = parent.superview;
                }
            }
        }
        scanAndClickButton(subview);
    }
}

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

// Lớp 4: Đổi text đỏ thành xanh và tự động đóng popup
%hook UILabel
- (void)setText:(NSString *)text {
    if ([text containsString:@"Thất bại"] || [text containsString:@"Không thể kích hoạt"] || [text containsString:@"Failed"]) {
        %orig(@"Thành công. Đã kích hoạt Filza!");
        
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"is_activated"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"activated"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *currentWindow = self.window;
            if (!currentWindow) return;
            UIViewController *rootVC = currentWindow.rootViewController;
            if (rootVC.presentedViewController) {
                [rootVC dismissViewControllerAnimated:YES completion:nil];
            }
        });
        return;
    }
    %orig;
}
%end

// Lớp 5: Mắt thần quét toàn bộ cửa sổ mỗi 0.5 giây
%ctor {
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                scanAndClickButton(window);
            }
        });
    }];
}
