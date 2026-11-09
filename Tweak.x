#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// 1. Chặn mạng, giả lập kích hoạt thành công
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

// 2. Đè kết quả JSON nếu nó parse
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

// 3. Ép mọi class của Filza (bắt đầu bằng TG) trả về TRUE nếu check bản quyền
%ctor {
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    objc_getClassList(classes, numClasses);

    for (int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        
        // Chỉ quét các class của Filza (thường có tiền tố TG)
        if ([className hasPrefix:@"TG"] || [className containsString:@"Preferences"]) {
            unsigned int methodCount;
            Method *methods = class_copyMethodList(cls, &methodCount);
            for (unsigned int j = 0; j < methodCount; j++) {
                NSString *methodName = NSStringFromSelector(method_getName(methods[j]));
                NSString *lowerMethod = [methodName lowercaseString];
                
                // Nếu hàm trả về bool và có chữ check bản quyền
                const char *typeEncoding = method_getTypeEncoding(methods[j]);
                if ((typeEncoding[0] == 'c' || typeEncoding[0] == 'B') && 
                   ([lowerMethod containsString:@"activ"] || [lowerMethod containsString:@"licens"] || [lowerMethod containsString:@"valid"] || [lowerMethod containsString:@"trial"] || [lowerMethod containsString:@"purchas"])) {
                    
                    IMP newImp = imp_implementationWithBlock(^BOOL(id _self) {
                        return YES;
                    });
                    method_setImplementation(methods[j], newImp);
                }
            }
            free(methods);
        }
    }
    free(classes);
}
%end

// 4. Tự động đổi chữ "Thất bại" thành "Thành công" trong UIAlertController
%hook UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)preferredStyle {
    if ([title containsString:@"Thất bại"] || [message containsString:@"Thất bại"] || [message containsString:@"Không thể kích hoạt"]) {
        return %orig(@"Thành công", @"Đã kích hoạt Filza vĩnh viễn!", UIAlertControllerStyleAlert);
    }
    return %orig;
}
%end

// 5. Tự động bấm nút Kích hoạt (nếu nó hiện bảng đòi nhập)
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
