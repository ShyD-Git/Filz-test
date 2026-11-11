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
    # MOV W0, #0 (Returns false) -> MOV W0, #1 (Returns true)
    MOV_W0_0 = b'\x00\x00\x80\x52'
    MOV_W0_1 = [0x20, 0x00, 0x80, 0x52]

    for binary in fat:
        print(f"[*] Processing architecture: {binary.header.cpu_type}")
        
        for symbol in binary.symbols:
            if any(k in symbol.name for k in ["Premium", "Transaction", "isActive", "Subscription", "isPro"]):
                if symbol.value >= binary.imagebase:
                    try:
                        bytes_at_addr = bytes(binary.get_content_from_virtual_address(symbol.value, 4))
                        
                        if bytes_at_addr == MOV_W0_0:
                            binary.patch_address(symbol.value, MOV_W0_1)
                            print(f"    [!] Patched {symbol.name} to return TRUE")
                            patched_count += 1
                    except Exception as e:
                        pass # Bỏ qua lỗi đọc hàm, tránh chết app

    if patched_count > 0:
        builder = lief.MachO.Builder(fat)
        builder.write(binary_path)
        print(f"[*] Patching complete. Modified {patched_count} targets.")
    else:
        print("[!] Cảnh báo: Không tìm thấy hàm nào cần vá. File có thể đã bị xáo trộn mã máy.")

if __name__ == "__main__":
    target_binary = "Payload/TempMail.app/TempMail"
    if os.path.exists(target_binary):
        patch_binary(target_binary)
    else:
        print("[-] Target binary not found!")
        sys.exit(1)
