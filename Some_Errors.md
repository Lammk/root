# Fix GPG Keys, DPKG and SSL Errors in PRoot Ubuntu/Debian
# Sửa Lỗi GPG Keys, DPKG và SSL trong PRoot Ubuntu/Debian

[English](#english) | [Tiếng Việt](#tieng-viet)

---

<a name="english"></a>
# 🇬🇧 English Version

## Common Issues

### 1. GPG Keys Error

When running `apt update` in proot environment with Ubuntu/Debian, you may encounter:

```
W: GPG error: http://archive.ubuntu.com/ubuntu jammy InRelease: 
   The following signatures couldn't be verified because the public key is not available: 
   NO_PUBKEY 871920D1991BC93C
E: The repository 'http://archive.ubuntu.com/ubuntu jammy InRelease' is not signed.
```

### 2. DPKG Error

When installing packages, you may encounter:

```
Errors were encountered while processing:
 libpaper1:amd64
 libgs9:amd64
 libpaper-utils
 ghostscript
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

### 3. SSL/Curl Error

When using curl or wget:

```
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

## Root Causes

### GPG Errors:
1. **Permission issues**: User `_apt` cannot read keyring files in `/etc/apt/trusted.gpg.d/`
2. **Missing GPG keys**: Proot environment lacks Ubuntu archive keys
3. **Proot limitations**: Some system calls related to GPG don't work properly in proot

### DPKG Errors:
1. **Post-install scripts fail**: Some packages try to run systemd/init scripts that don't work in proot
2. **Service management**: Packages try to start services (ghostscript, cups, etc.)
3. **Missing dependencies**: Proot doesn't fully support system calls for some operations

### SSL Errors:
1. **Missing CA certificates**: Fresh Ubuntu base images don't include ca-certificates package
2. **Environment variables not set**: SSL_CERT_FILE and CURL_CA_BUNDLE not configured
3. **Certificate paths**: curl/wget can't find certificate bundle

## Solutions Integrated in Script

The `root.sh` script automatically fixes these issues:

### 1. Auto-fix during installation
- **GPG**: Fix permissions for all `.gpg` files
- **GPG**: Create apt config to allow unauthenticated repositories
- **DPKG**: Create `/usr/sbin/policy-rc.d` to prevent services from auto-starting
- **DPKG**: Create fake `systemctl` to avoid service management errors
- **DPKG**: Configure dpkg with `--force-confold`, `--force-overwrite`
- **SSL**: Pre-configure SSL environment variables in .bashrc
- **SSL**: Create ca-certificates directory structure
- Create scripts: `fix-apt-keys`, `fix-dpkg-errors`, and `fix-ssl-certs`

### 2. Auto-fix during startup
- Automatically run `fix-apt-keys` on first boot
- Install ca-certificates package automatically
- Filter warnings to avoid user confusion
- Still allow apt to work despite warnings
- Guide users to use `--no-install-recommends` to avoid dpkg errors

## Manual Usage (if needed)

### Inside proot environment:

#### Method 1: Use built-in scripts

**Fix GPG:**
```bash
fix-apt-keys
apt update
```

**Fix DPKG:**
```bash
fix-dpkg-errors
apt install -y --no-install-recommends <package>
```

**Fix SSL:**
```bash
fix-ssl-certs
source ~/.bashrc
curl https://google.com  # Test
```

#### Method 2: Manual GPG fix
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

#### Method 3: Bypass GPG check
```bash
# Temporarily allow unauthenticated
apt update --allow-insecure-repositories

# Install package without GPG check
apt install -y --allow-unauthenticated <package_name>
```

#### Method 4: Manual DPKG fix
```bash
# Remove broken packages
dpkg --purge --force-all libpaper1 libgs9 libpaper-utils ghostscript

# Fix dpkg database
dpkg --configure -a
apt-get install -f -y

# Clean and update
apt-get clean
rm -rf /var/lib/apt/lists/*
apt-get update

# Reinstall with --no-install-recommends
apt install -y --no-install-recommends <package>
```

#### Method 5: Manual SSL fix
```bash
# Install ca-certificates
apt install -y --no-install-recommends ca-certificates

# Update certificates
update-ca-certificates --fresh

# Set environment variables
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export SSL_CERT_DIR=/etc/ssl/certs
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# Add to .bashrc for persistence
cat >> ~/.bashrc << 'EOF'
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
EOF
```

#### Method 6: Installing packages with services (NEW!)

**Good news!** You can now install packages with services:

```bash
# These now work! (services won't run, but packages install fine)
apt install -y mysql-server postgresql nginx apache2 ghostscript cups

# The binaries work even though services don't run
mysql --version
psql --version
nginx -v

# systemctl won't crash, just shows inactive
systemctl status mysql
# Output: Active: inactive (dead)

# Use client tools to connect to remote servers
mysql -h remote_host -u user -p
psql -h remote_host -U user
```

#### Method 7: Best practices for package installation
```bash
# Recommended: use --no-install-recommends (fewer dependencies)
apt install -y --no-install-recommends vim curl wget

# But you can also install with full dependencies if needed
apt install -y mysql-server  # Works now!

# If package must be installed with force
dpkg -i --force-all package.deb
```

## Important Ubuntu GPG Keys

- **871920D1991BC93C**: Ubuntu Archive Automatic Signing Key (2018)
- **3B4FE6ACC0B21F32**: Ubuntu Archive Automatic Signing Key (2012)
- **790BC7277767219C**: Ubuntu Archive Automatic Signing Key (2022)

## Security Notes

⚠️ **WARNING**: Disabling GPG verification reduces security!

- Only use in test/development environments
- Don't use for production systems
- Proot environment is not a security boundary anyway

## Verification

```bash
# Check permissions
ls -la /etc/apt/trusted.gpg.d/

# Check apt config
cat /etc/apt/apt.conf.d/99-proot-no-check

# Check SSL certificates
ls -la /etc/ssl/certs/ca-certificates.crt
echo $SSL_CERT_FILE

# Test apt update
apt update 2>&1 | grep -E "^(E:|W:)"

# Test curl
curl -v https://google.com 2>&1 | grep -i certificate
```

## Troubleshooting

### Still getting GPG errors after fix?

1. **Clear cache and retry**:
   ```bash
   rm -rf /var/lib/apt/lists/*
   apt clean
   apt update
   ```

2. **Try different keyserver**:
   ```bash
   apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 871920D1991BC93C
   ```

3. **Reinstall keyring package**:
   ```bash
   apt install --reinstall --allow-unauthenticated ubuntu-keyring
   ```

### Still getting DPKG errors after fix?

1. **Check broken packages**:
   ```bash
   dpkg -l | grep "^iU"  # Packages unconfigured
   dpkg -l | grep "^iF"  # Packages failed
   ```

2. **Force remove all broken packages**:
   ```bash
   dpkg -l | grep "^iU\|^iF" | awk '{print $2}' | xargs dpkg --purge --force-all
   ```

3. **Check policy-rc.d**:
   ```bash
   cat /usr/sbin/policy-rc.d
   # Must return exit code 101
   ```

4. **Check fake systemctl**:
   ```bash
   which systemctl
   systemctl status test  # Should not crash
   ```

### Still getting SSL errors after fix?

1. **Verify ca-certificates installed**:
   ```bash
   dpkg -l | grep ca-certificates
   ```

2. **Check certificate file exists**:
   ```bash
   ls -la /etc/ssl/certs/ca-certificates.crt
   ```

3. **Verify environment variables**:
   ```bash
   echo $SSL_CERT_FILE
   echo $CURL_CA_BUNDLE
   ```

4. **Test with verbose output**:
   ```bash
   curl -v https://google.com
   wget --debug https://google.com
   ```

### Reinstall from scratch

```bash
# Exit proot
exit

# Remove and reinstall
bash root.sh -r
```

## References

- Ubuntu Keys: https://wiki.ubuntu.com/SecurityTeam/FAQ#GPG_Keys
- APT Secure: `man apt-secure`
- Proot Documentation: https://proot-me.github.io/
- CA Certificates: `man update-ca-certificates`

---

<a name="tieng-viet"></a>
# 🇻🇳 Phiên Bản Tiếng Việt

## Các vấn đề thường gặp

### 1. Lỗi GPG Keys

Khi chạy `apt update` trong proot environment với Ubuntu/Debian, bạn có thể gặp lỗi:

```
W: GPG error: http://archive.ubuntu.com/ubuntu jammy InRelease: 
   The following signatures couldn't be verified because the public key is not available: 
   NO_PUBKEY 871920D1991BC93C
E: The repository 'http://archive.ubuntu.com/ubuntu jammy InRelease' is not signed.
```

### 2. Lỗi DPKG

Khi cài đặt packages, bạn có thể gặp lỗi:

```
Errors were encountered while processing:
 libpaper1:amd64
 libgs9:amd64
 libpaper-utils
 ghostscript
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

### 3. Lỗi SSL/Curl

Khi sử dụng curl hoặc wget:

```
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

## Nguyên nhân

### Lỗi GPG:
1. **Permission issues**: User `_apt` không thể đọc keyring files trong `/etc/apt/trusted.gpg.d/`
2. **Missing GPG keys**: Proot environment thiếu Ubuntu archive keys
3. **Proot limitations**: Một số system calls liên quan đến GPG không hoạt động đúng trong proot

### Lỗi DPKG:
1. **Post-install scripts fail**: Một số packages cố gắng chạy systemd/init scripts không hoạt động trong proot
2. **Service management**: Packages cố khởi động services (ghostscript, cups, etc.)
3. **Missing dependencies**: Proot không hỗ trợ đầy đủ system calls cho một số operations

### Lỗi SSL:
1. **Thiếu CA certificates**: Ubuntu base images mới không bao gồm package ca-certificates
2. **Biến môi trường chưa set**: SSL_CERT_FILE và CURL_CA_BUNDLE chưa được cấu hình
3. **Đường dẫn certificates**: curl/wget không tìm thấy certificate bundle

## Giải pháp đã tích hợp trong script

Script `root.sh` đã tự động fix các vấn đề này:

### 1. Auto-fix khi cài đặt
- **GPG**: Fix permissions cho tất cả `.gpg` files
- **GPG**: Tạo apt config để allow unauthenticated repositories
- **DPKG**: Tạo `/usr/sbin/policy-rc.d` để ngăn services tự khởi động
- **DPKG**: Tạo fake `systemctl` để tránh lỗi service management
- **DPKG**: Configure dpkg với `--force-confold`, `--force-overwrite`
- **SSL**: Pre-configure biến môi trường SSL trong .bashrc
- **SSL**: Tạo cấu trúc thư mục ca-certificates
- Tạo scripts: `fix-apt-keys`, `fix-dpkg-errors`, và `fix-ssl-certs`

### 2. Auto-fix khi khởi động
- Tự động chạy `fix-apt-keys` lần đầu tiên
- Tự động cài đặt package ca-certificates
- Filter warnings để không làm user hoang mang
- Vẫn cho phép apt hoạt động dù có warnings
- Hướng dẫn dùng `--no-install-recommends` để tránh lỗi dpkg

## Cách sử dụng thủ công (nếu cần)

### Trong proot environment:

#### Phương pháp 1: Dùng scripts có sẵn

**Fix GPG:**
```bash
fix-apt-keys
apt update
```

**Fix DPKG:**
```bash
fix-dpkg-errors
apt install -y --no-install-recommends <package>
```

**Fix SSL:**
```bash
fix-ssl-certs
source ~/.bashrc
curl https://google.com  # Test
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

#### Phương pháp 4: Fix DPKG errors thủ công
```bash
# Xóa packages lỗi
dpkg --purge --force-all libpaper1 libgs9 libpaper-utils ghostscript

# Fix dpkg database
dpkg --configure -a
apt-get install -f -y

# Clean và update
apt-get clean
rm -rf /var/lib/apt/lists/*
apt-get update

# Cài lại với --no-install-recommends
apt install -y --no-install-recommends <package>
```

#### Phương pháp 5: Fix SSL thủ công
```bash
# Cài đặt ca-certificates
apt install -y --no-install-recommends ca-certificates

# Update certificates
update-ca-certificates --fresh

# Set biến môi trường
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export SSL_CERT_DIR=/etc/ssl/certs
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# Thêm vào .bashrc để lưu vĩnh viễn
cat >> ~/.bashrc << 'EOF'
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
EOF
```

#### Phương pháp 6: Cài packages có services (MỚI!)

**Tin tốt!** Giờ có thể cài packages có services:

```bash
# Các packages này giờ hoạt động! (services không chạy, nhưng packages cài được)
apt install -y mysql-server postgresql nginx apache2 ghostscript cups

# Binaries hoạt động dù services không chạy
mysql --version
psql --version
nginx -v

# systemctl không crash, chỉ hiện inactive
systemctl status mysql
# Output: Active: inactive (dead)

# Dùng client tools để kết nối remote servers
mysql -h remote_host -u user -p
psql -h remote_host -U user
```

#### Phương pháp 7: Best practices khi cài packages
```bash
# Khuyến nghị: dùng --no-install-recommends (ít dependencies hơn)
apt install -y --no-install-recommends vim curl wget

# Nhưng cũng có thể cài với full dependencies nếu cần
apt install -y mysql-server  # Giờ hoạt động!

# Nếu package bắt buộc phải cài với force
dpkg -i --force-all package.deb
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

### Vẫn gặp lỗi GPG sau khi fix?

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

### Vẫn gặp lỗi DPKG sau khi fix?

1. **Kiểm tra packages bị lỗi**:
   ```bash
   dpkg -l | grep "^iU"  # Packages unconfigured
   dpkg -l | grep "^iF"  # Packages failed
   ```

2. **Force remove tất cả packages lỗi**:
   ```bash
   dpkg -l | grep "^iU\|^iF" | awk '{print $2}' | xargs dpkg --purge --force-all
   ```

3. **Kiểm tra policy-rc.d**:
   ```bash
   cat /usr/sbin/policy-rc.d
   # Phải return exit code 101
   ```

4. **Kiểm tra fake systemctl**:
   ```bash
   which systemctl
   systemctl status test  # Phải không crash
   ```

### Cài đặt lại từ đầu

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
