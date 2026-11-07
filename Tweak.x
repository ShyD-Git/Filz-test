#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Mock API response cho môi trường QA nội bộ
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSString *url = request.URL.absoluteString;
    if ([url containsString:@"activate"] || [url containsString:@"license"] || [url containsString:@"tigi"]) {
        NSData *mockData = [@"{\"status\":\"success\",\"env\":\"qa\"}" dataUsingEncoding:NSUTF8StringEncoding];
        NSHTTPURLResponse *mockResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        if (completionHandler) {
            completionHandler(mockData, mockResponse, nil);
        }
        return nil; 
    }
    return %orig;
}
%end

// Tự động quét và mock các giá trị Boolean lúc app vừa khởi động
%ctor {
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    objc_getClassList(classes, numClasses);

    for (int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        NSString *lowerName = [className lowercaseString];
        
        // Nhắm vào các class kiểm tra bản quyền
        if ([lowerName containsString:@"license"] || 
            [lowerName containsString:@"activat"] || 
            [lowerName containsString:@"verify"] ||
            [lowerName containsString:@"tigi"]) {
            
            unsigned int methodCount;
            Method *methods = class_copyMethodList(cls, &methodCount);
            for (unsigned int j = 0; j < methodCount; j++) {
                const char *typeEncoding = method_getTypeEncoding(methods[j]);
                
                // Nếu hàm trả về BOOL (c hoặc B)
                if (typeEncoding[0] == 'c' || typeEncoding[0] == 'B') {
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
