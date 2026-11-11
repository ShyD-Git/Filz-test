import lief
import os
import sys

def patch_binary(binary_path):
    fat = lief.MachO.parse(binary_path)
    if fat is None:
        return 0

    patched_count = 0
    # MOV W0, #0 (Returns false) -> MOV W0, #1 (Returns true)
    MOV_W0_0 = b'\x00\x00\x80\x52'
    MOV_W0_1 = b'\x20\x00\x80\x52'

    for binary in fat:
        for symbol in binary.symbols:
            # value > 0 nghĩa là hàm thực sự nằm trong file này (không phải import từ ngoài)
            if symbol.value >= binary.imagebase and symbol.value > 0:
                name = symbol.name.lower()
                
                # Nếu là hàm check Premium/Active -> Ép trả về TRUE
                if any(k in name for k in ["ispremium", "isactive", "ispro", "haspurchased", "issubscribed"]):
                    try:
                        bytes_at_addr = bytes(binary.get_content_from_virtual_address(symbol.value, 4))
                        if bytes_at_addr == MOV_W0_0:
                            binary.patch_address(symbol.value, list(MOV_W0_1))
                            print(f"    [!] Patched to TRUE: {symbol.name}")
                            patched_count += 1
                    except Exception: pass
                
                # Nếu là hàm check hết hạn -> Ép trả về FALSE
                elif any(k in name for k in ["isexpired", "istrialused"]):
                    try:
                        bytes_at_addr = bytes(binary.get_content_from_virtual_address(symbol.value, 4))
                        if bytes_at_addr == MOV_W0_1:
                            binary.patch_address(symbol.value, list(MOV_W0_0))
                            print(f"    [!] Patched to FALSE: {symbol.name}")
                            patched_count += 1
                    except Exception: pass

    if patched_count > 0:
        builder = lief.MachO.Builder(fat)
        builder.write(binary_path)
    return patched_count

if __name__ == "__main__":
    app_path = "Payload/TempMail.app"
    total_patched = 0
    
    print(f"[*] Quét toàn bộ App Bundle: {app_path}")
    
    # Quét đệ quy mọi file trong thư mục App (bao gồm cả Frameworks)
    for root, dirs, files in os.walk(app_path):
        for file in files:
            file_path = os.path.join(root, file)
            # Chỉ xử lý các file là Mach-O Binary (thường là file thực thi)
            try:
                if lief.is_macho(file_path):
                    print(f"[*] Đang mổ file: {file_path}")
                    patched = patch_binary(file_path)
                    total_patched += patched
                    if patched > 0:
                        print(f"    -> Đã vá {patched} hàm.")
            except Exception as e:
                pass

    print(f"[*] TỔNG KẾT: Đã vá thành công {total_patched} hàm.")
    if total_patched == 0:
        print("[!] CẢNH BÁO: Không tìm thấy hàm nào để vá. App có thể dùng StoreKit 2 JWS.")
