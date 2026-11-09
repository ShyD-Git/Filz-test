#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// Khai báo Interface
@interface NewActivationViewController : UIViewController
- (void)activate:(id)arg1;
- (void)activateFromURL:(id)arg1;
@end

@interface TGRootFileManager : NSObject
- (id)fetchActivationSignature;
@end

@interface TGPreferences : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isActivated;
- (void)setIsActivated:(BOOL)arg1;
@end

@interface TGPreferencesTableViewController : UITableViewController
- (id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
@end

// Hàm đệ quy quét sạch mọi ngóc ngách của UIView
static void replaceTrialText(UIView *view) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)subview;
            if ([lbl.text containsString:@"DÙNG THỬ"] || [lbl.text containsString:@"Dùng thử"]) {
                lbl.text = @"VĨNH VIỄN";
                lbl.textColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0]; // Xanh lá
            }
        }
        replaceTrialText(subview);
    }
}

// 1. Chặn hàm kích hoạt
%hook NewActivationViewController
- (void)activate:(id)arg1 {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thành công" message:@"Đã kích hoạt Filza vĩnh viễn!" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}
- (void)activateFromURL:(id)arg1 {
    [self activate:arg1];
}
%end

// 2. Giả mạo chữ ký
%hook TGRootFileManager
- (id)fetchActivationSignature {
    return @"Minecraft_Lifetime_Signature_2026";
}
%end

// 3. Ép class TGPreferences luôn báo VIP
%hook TGPreferences
- (BOOL)isActivated {
    return YES;
}
%end

// 4. Quét sạch bảng Tùy chỉnh
%hook TGPreferencesTableViewController
- (id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id cell = %orig;
    replaceTrialText(cell);
    return cell;
}
%end
