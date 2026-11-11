import lief
import os
import sys

def patch_binary(binary_path):
    print(f"[*] Analyzing binary: {binary_path}")
    fat = lief.MachO.parse(binary_path)
    
    if fat is None:
        print("[-] Failed to parse MachO binary.")
        sys.exit(1)

    patched_count = 0
    # ARM64 Opcodes
    # MOV W0, #0 (00 00 80 52) -> Returns false
    # MOV W0, #1 (20 00 80 52) -> Returns true
    MOV_W0_0 = b'\x00\x00\x80\x52'

    for binary in fat:
        print(f"[*] Processing architecture: {binary.header.cpu_type}")
        
        # Quét qua toàn bộ symbol (Tên hàm)
        for symbol in binary.symbols:
            # Nhắm vào các hàm Swift liên quan đến Premium
            if any(k in symbol.name for k in ["Premium", "Transaction", "isActive", "Subscription", "isPro"]):
                print(f"[+] Found relevant symbol: {symbol.name}")
                if symbol.value >= binary.imagebase:
                    try:
                        # Đọc 4 byte tại địa chỉ của hàm
                        bytes_at_addr = bytes(binary.get_content_from_virtual_address(symbol.value, 4))
                        
                        # Nếu hàm bắt đầu bằng lệnh trả về False, đổi thành True
                        if bytes_at_addr == MOV_W0_0:
                            binary.patch_address(symbol.value, [0x20, 0x00, 0x80, 0x52])
                            print(f"    [!] Patched {symbol.name} to return TRUE")
                            patched_count += 1
                    except Exception as e:
                        print(f"    [-] Error patching {symbol.name}: {e}")

    # Lưu lại file binary đã được vá
    builder = lief.MachO.Builder(fat)
    builder.write(binary_path)
    print(f"[*] Patching complete. Modified {patched_count} targets.")

if __name__ == "__main__":
    target_binary = "Payload/TempMail.app/TempMail"
    if os.path.exists(target_binary):
        patch_binary(target_binary)
    else:
        print("[-] Target binary not found!")
        sys.exit(1)
