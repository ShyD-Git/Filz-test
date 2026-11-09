#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// 1. Chặn hàm kích hoạt, giả lập thành công
%hook NewActivationViewController
- (void)activate:(id)arg1 {
    // Không gọi %orig để chặn đứng việc gửi request lên server
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

// 2. Giả mạo chữ ký kích hoạt
%hook TGRootFileManager
- (id)fetchActivationSignature {
    return @"Minecraft_Lifetime_Signature_2026";
}
%end

// 3. Sửa giao diện bảng Tùy chỉnh (Ép chữ Vĩnh Viễn)
%hook TGPreferencesTableViewController
- (id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id cell = %orig;
    
    // Quét tìm UILabel để đổi chữ
    for (UIView *view in [cell subviews]) {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)view;
            if ([lbl.text containsString:@"Dùng thử"] || [lbl.text containsString:@"Chưa kích hoạt"] || [lbl.text containsString:@"DÙNG THỬ"]) {
                lbl.text = @"VĨNH VIỄN";
                lbl.textColor = [UIColor systemGreenColor];
            }
        }
    }
    return cell;
}
- (void)updateLicense {
    // Bỏ qua hàm gốc để không bị check mạng
}
%end
