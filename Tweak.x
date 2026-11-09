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

// 2. Đè kết quả JSON
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

// 3. Bắt trọn ổ NSUserDefaults (Bản quyền, kích hoạt)
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    NSString *lower = [defaultName lowercaseString];
    if ([lower containsString:@"activat"] || [lower containsString:@"licens"] || [lower containsString:@"valid"] || [lower containsString:@"tigi"] || [lower containsString:@"trial"]) {
        return YES;
    }
    return %orig;
}
- (NSInteger)integerForKey:(NSString *)defaultName {
    NSString *lower = [defaultName lowercaseString];
    if ([lower containsString:@"activat"] || [lower containsString:@"licens"] || [lower containsString:@"valid"] || [lower containsString:@"tigi"] || [lower containsString:@"trial"]) {
        return 1;
    }
    return %orig;
}
%end

// 4. Hook UITableViewCell đổi chữ "DÙNG THỬ" thành "VĨNH VIỄN"
%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    for (UIView *view in self.contentView.subviews) {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)view;
            if ([lbl.text containsString:@"DÙNG THỬ"] || [lbl.text containsString:@"Dùng thử"] || [lbl.text containsString:@"Chưa kích hoạt"]) {
                lbl.text = @"VĨNH VIỄN";
                lbl.textColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0]; // Màu xanh lá
            }
        }
    }
}
%end

// 5. Hook UILabel (Bỏ qua UITableViewLabel để không crash)
%hook UILabel
- (void)setText:(NSString *)text {
    if ([NSStringFromClass([self class]) isEqualToString:@"UITableViewLabel"]) {
        %orig;
        return;
    }
    if ([text containsString:@"Thất bại"] || [text containsString:@"Không thể kích hoạt"]) {
        %orig(@"Thành công. Đã kích hoạt!");
        return;
    }
    %orig;
}
%end

// 6. Quét các class TG* ép hàm logic trả về True
%ctor {
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    objc_getClassList(classes, numClasses);

    for (int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        
        if ([className hasPrefix:@"TG"] || [className containsString:@"License"] || [className containsString:@"Activation"] || [className containsString:@"Serial"]) {
            unsigned int methodCount;
            Method *methods = class_copyMethodList(cls, &methodCount);
            for (unsigned int j = 0; j < methodCount; j++) {
                NSString *methodName = NSStringFromSelector(method_getName(methods[j]));
                NSString *lowerMethod = [methodName lowercaseString];
                const char *typeEncoding = method_getTypeEncoding(methods[j]);
                
                if (typeEncoding) {
                    if ((typeEncoding[0] == 'B' || typeEncoding[0] == 'c' || typeEncoding[0] == 'i' || typeEncoding[0] == 'q') && 
                       ([lowerMethod containsString:@"activ"] || [lowerMethod containsString:@"licens"] || [lowerMethod containsString:@"valid"] || [lowerMethod containsString:@"serial"] || [lowerMethod containsString:@"trial"])) {
                        
                        IMP newImp = imp_implementationWithBlock(^NSInteger(id _self) {
                            return 1;
                        });
                        method_setImplementation(methods[j], newImp);
                    }
                    else if (typeEncoding[0] == '@') {
                        if ([lowerMethod containsString:@"licensestatus"] || [lowerMethod containsString:@"statustext"] || [lowerMethod containsString:@"getstate"]) {
                             IMP newImp = imp_implementationWithBlock(^id(id _self) {
                                return @"Vĩnh viễn";
                            });
                            method_setImplementation(methods[j], newImp);
                        }
                    }
                }
            }
            free(methods);
        }
    }
    free(classes);
}

// 7. Tự động bấm nút Kích hoạt
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
