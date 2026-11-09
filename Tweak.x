#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <SystemConfiguration/SystemConfiguration.h>

// Hàm C đệ quy tự động tìm và bấm nút
static void forceActivate(UIView *view) {
    if (!view) return;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)subview;
            if ([[btn titleForState:UIControlStateNormal] containsString:@"Kích hoạt"] || 
                [[btn titleForState:UIControlStateNormal] containsString:@"Activate"]) {
                [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                NSLog(@"[QA-MOCK] Auto-click UIButton!");
                return;
            }
        } else if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)subview;
            if ([lbl.text containsString:@"Kích hoạt"] || [lbl.text containsString:@"Activate"]) {
                UIView *parent = lbl.superview;
                while (parent) {
                    if ([parent isKindOfClass:[UIControl class]]) {
                        [(UIControl *)parent sendActionsForControlEvents:UIControlEventTouchUpInside];
                        NSLog(@"[QA-MOCK] Auto-click Cell Label!");
                        return;
                    }
                    parent = parent.superview;
                }
            }
        }
        forceActivate(subview);
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

// Lớp 2: Lừa app là đang có kết nối Internet (Fix lỗi "Cần kết nối internet")
%hook SCNetworkReachability
- (BOOL)getFlags:(SCNetworkReachabilityFlags *)flags {
    if (flags) {
        *flags = kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsConnectionRequired | kSCNetworkReachabilityFlagsConnectionOnTraffic;
    }
    return YES;
}
%end

// Lớp 3: Chặn API mạng, giả lập server trả về thành công
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

// Lớp 4: Chặn popup thông báo
%hook UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    if ([viewControllerToPresent isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewControllerToPresent;
        if ([alert.title containsString:@"Chưa kích hoạt"] || [alert.message containsString:@"Kích hoạt Filza"]) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"is_activated"];
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"activated"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            for (UIAlertAction *action in alert.actions) {
                if ([action.title containsString:@"Kích hoạt"]) {
                    void (^handler)(UIAlertAction *) = [action valueForKey:@"handler"];
                    if (handler) handler(action);
                    break;
                }
            }
            return; 
        }
    }
    %orig;
}
%end

// Lớp 5: Tự động bấm nút Kích hoạt sau khi màn hình hiện ra 1 giây
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            forceActivate(window);
        }
    });
}
%end
