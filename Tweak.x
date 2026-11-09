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
- (void)updateLicense;
- (void)openLicenseDialog;
- (id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
@end

// Hàm đệ quy đổi chữ
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

// 1. Bắt tận tay mọi popup "Chưa kích hoạt" và đập nát nó
%hook UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    if ([viewControllerToPresent isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewControllerToPresent;
        if ([alert.title containsString:@"Chưa kích hoạt"] || [alert.message containsString:@"Kích hoạt Filza"] || [alert.message containsString:@"Sẽ đóng trong"]) {
            // Đéo hiển thị popup, đéo làm gì cả
            NSLog(@"[QA-MOCK] Đã chặn popup Chưa kích hoạt!");
            return; 
        }
    }
    %orig;
}
%end

// 2. Chặn hàm kích hoạt (nếu mày bấm vào nút Kích hoạt thì nó báo thành công luôn)
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

// 3. Giả mạo chữ ký
%hook TGRootFileManager
- (id)fetchActivationSignature {
    return @"Minecraft_Lifetime_Signature_2026";
}
%end

// 4. Ép class TGPreferences luôn báo VIP
%hook TGPreferences
- (BOOL)isActivated {
    return YES;
}
%end

// 5. Dẹp giao diện Tùy chỉnh và chặn mở hộp thoại
%hook TGPreferencesTableViewController
- (void)updateLicense {
    // Đéo check mạng
}
- (void)openLicenseDialog {
    // Đéo mở bảng chọn mua
}
- (id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id cell = %orig;
    replaceTrialText(cell);
    return cell;
}
%end
