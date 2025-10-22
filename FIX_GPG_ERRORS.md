# Fix Lỗi GPG Keys trong PRoot Ubuntu/Debian

## Vấn đề

Khi chạy `apt update` trong proot environment với Ubuntu/Debian, bạn có thể gặp lỗi:

```
W: GPG error: http://archive.ubuntu.com/ubuntu jammy InRelease: 
   The following signatures couldn't be verified because the public key is not available: 
   NO_PUBKEY 871920D1991BC93C
E: The repository 'http://archive.ubuntu.com/ubuntu jammy InRelease' is not signed.
```

## Nguyên nhân

1. **Permission issues**: User `_apt` không thể đọc keyring files trong `/etc/apt/trusted.gpg.d/`
2. **Missing GPG keys**: Proot environment thiếu Ubuntu archive keys
3. **Proot limitations**: Một số system calls liên quan đến GPG không hoạt động đúng trong proot

## Giải pháp đã tích hợp trong script

Script `root.sh` đã tự động fix các vấn đề này:

### 1. Auto-fix khi cài đặt
- Fix permissions cho tất cả `.gpg` files
- Tạo apt config để allow unauthenticated repositories
- Tạo script `fix-apt-keys` sẵn trong rootfs

### 2. Auto-fix khi khởi động
- Tự động chạy `fix-apt-keys` lần đầu tiên
- Filter warnings để không làm user hoang mang
- Vẫn cho phép apt hoạt động dù có GPG warnings

## Cách sử dụng thủ công (nếu cần)

### Trong proot environment:

#### Phương pháp 1: Dùng script có sẵn
```bash
fix-apt-keys
apt update
```

#### Phương pháp 2: Fix permissions thủ công
```bash
# Fix permissions
chmod 644 /etc/apt/trusted.gpg.d/*.gpg
chmod 755 /etc/apt/trusted.gpg.d
mkdir -p /var/lib/apt/lists/partial
chmod 755 /var/lib/apt/lists

# Import keys
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 871920D1991BC93C
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3B4FE6ACC0B21F32
```

#### Phương pháp 3: Bypass GPG check
```bash
# Tạm thời cho phép unauthenticated
apt update --allow-insecure-repositories

# Cài package mà không check GPG
apt install -y --allow-unauthenticated <package_name>
```

#### Phương pháp 4: Disable GPG check hoàn toàn
```bash
cat > /etc/apt/apt.conf.d/99-no-check << 'EOF'
Acquire::AllowInsecureRepositories "true";
APT::Get::AllowUnauthenticated "true";
EOF

apt update
```

## Các GPG keys quan trọng của Ubuntu

- **871920D1991BC93C**: Ubuntu Archive Automatic Signing Key (2018)
- **3B4FE6ACC0B21F32**: Ubuntu Archive Automatic Signing Key (2012)
- **790BC7277767219C**: Ubuntu Archive Automatic Signing Key (2022)

## Lưu ý bảo mật

⚠️ **CẢNH BÁO**: Việc disable GPG verification làm giảm bảo mật!

- Chỉ nên dùng trong môi trường test/development
- Không dùng cho production systems
- Proot environment vốn đã không phải là security boundary

## Kiểm tra xem fix đã hoạt động chưa

```bash
# Kiểm tra permissions
ls -la /etc/apt/trusted.gpg.d/

# Kiểm tra apt config
cat /etc/apt/apt.conf.d/99-proot-no-check

# Test apt update
apt update 2>&1 | grep -E "^(E:|W:)"
```

## Troubleshooting

### Vẫn gặp lỗi sau khi fix?

1. **Xóa cache và thử lại**:
   ```bash
   rm -rf /var/lib/apt/lists/*
   apt clean
   apt update
   ```

2. **Thử keyserver khác**:
   ```bash
   apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 871920D1991BC93C
   ```

3. **Reinstall keyring package**:
   ```bash
   apt install --reinstall --allow-unauthenticated ubuntu-keyring
   ```

4. **Cài đặt lại từ đầu**:
   ```bash
   # Thoát proot
   exit
   
   # Xóa và cài lại
   bash root.sh -r
   ```

## Tham khảo

- Ubuntu Keys: https://wiki.ubuntu.com/SecurityTeam/FAQ#GPG_Keys
- APT Secure: `man apt-secure`
- Proot Documentation: https://proot-me.github.io/
