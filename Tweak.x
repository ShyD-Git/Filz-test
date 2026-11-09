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

// 2. Can thiệp thẳng vào bảng Tùy chỉnh để đổi chữ "Dùng thử" thành "Vĩnh viễn"
%hook TGPreferencesTableViewController
- (id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id cell = %orig;
    
    // Quét tìm label trong cell và đổi chữ
    for (UIView *view in [cell subviews]) {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)view;
            if ([lbl.text containsString:@"Dùng thử"] || [lbl.text containsString:@"Chưa kích hoạt"]) {
                lbl.text = @"Vĩnh viễn";
                lbl.textColor = [UIColor systemBlueColor]; // Đổi màu xanh cho đẹp
            }
        }
    }
    return cell;
}
%end

// 3. Hook UILabel an toàn (Chỉ đổi chữ Thất bại, bỏ qua UITableViewLabel để không crash)
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

// 4. Ép logic cốt lõi của Filza trả về True
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
                
                if (typeEncoding && (typeEncoding[0] == 'B' || typeEncoding[0] == 'c' || typeEncoding[0] == 'i' || typeEncoding[0] == 'q') && 
                   ([lowerMethod containsString:@"activ"] || [lowerMethod containsString:@"licens"] || [lowerMethod containsString:@"valid"] || [lowerMethod containsString:@"serial"] || [lowerMethod containsString:@"trial"])) {
                    
                    IMP newImp = imp_implementationWithBlock(^NSInteger(id _self) {
                        return 1;
                    });
                    method_setImplementation(methods[j], newImp);
                }
            }
            free(methods);
        }
    }
    free(classes);
}

// 5. Chặn popup báo lỗi, thay bằng thông báo thành công
%hook UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)preferredStyle {
    if ([title containsString:@"Thất bại"] || [message containsString:@"Thất bại"] || [message containsString:@"Không thể kích hoạt"]) {
        return %orig(@"Thành công", @"Đã kích hoạt Filza vĩnh viễn!", UIAlertControllerStyleAlert);
    }
    return %orig;
}
%end
