// --- 1. Giả Lập JWS Receipt Cho StoreKit 2 ---
%hook NSBundle
- (NSURL *)appStoreReceiptURL {
    // Đã xóa dòng NSURL *original = %orig; ở đây
    NSString *docsDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *fakePath = [docsDir stringByAppendingPathComponent:@"fake_receipt"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:fakePath]) {
        // Chuỗi JSON giả lập JWS (Payload chứa thông tin Premium)
        NSString *fakeJWS = @"{\"status\":0,\"environment\":\"Production\",\"receipt\":{\"bundle_id\":\"com.tempmail.ios\",\"in_app\":[{\"product_id\":\"premium_monthly\",\"purchase_date_ms\":\"1700000000000\"}]}}";
        [fakeJWS writeToFile:fakePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return [NSURL fileURLWithPath:fakePath];
}
%end
