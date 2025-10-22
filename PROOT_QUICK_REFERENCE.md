# PRoot Fake Root - Quick Reference / Tham Khảo Nhanh

[English](#english) | [Tiếng Việt](#tieng-viet)

---

<a name="english"></a>
# 🇬🇧 English Version

## 🚀 Quick Start

```bash
# Install and start
bash root.sh

# Install specific distro
bash root.sh -i

# Reinstall from scratch
bash root.sh -r

# Remove rootfs
bash root.sh -u
```

## 📦 Installing Packages

### Ubuntu/Debian (⭐ Ubuntu 22.04 Recommended)
```bash
# CORRECT way (avoid dpkg errors)
apt install -y --no-install-recommends <package>

# Examples
apt update
apt install -y --no-install-recommends vim curl wget git python3 nodejs

# Avoid these packages (often fail in proot)
# ❌ ghostscript, cups, avahi-daemon, systemd-related packages
```

### Alpine Linux
```bash
apk update
apk add vim curl wget git python3 nodejs
```

### Arch Linux
```bash
pacman -Syu
pacman -S vim curl wget git python3 nodejs
```

## 🔧 Fixing Common Errors

### GPG Error "NO_PUBKEY"
```bash
# Method 1: Use built-in script
fix-apt-keys

# Method 2: Bypass GPG
apt update --allow-insecure-repositories
apt install -y --allow-unauthenticated <package>
```

### DPKG Error "Sub-process returned error code (1)"
```bash
# Method 1: Use built-in script
fix-dpkg-errors

# Method 2: Manual fix
dpkg --configure -a
apt install -f -y
apt clean

# Method 3: Remove broken packages
dpkg --purge --force-all libpaper1 libgs9 ghostscript

# Method 4: Always use --no-install-recommends
apt install -y --no-install-recommends <package>
```

### SSL/Curl Error "certificate verify failed"
```bash
# Method 1: Use built-in script
fix-ssl-certs
source ~/.bashrc

# Method 2: Manual fix
apt install -y --no-install-recommends ca-certificates
update-ca-certificates --fresh

# Method 3: Set environment variables
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
```

## 🛠️ Built-in Tools

```bash
fix-apt-keys        # Fix GPG keys
fix-dpkg-errors     # Fix dpkg errors
fix-ssl-certs       # Fix SSL/curl errors
systemctl           # Fake systemctl (does nothing)
```

## 📝 Best Practices

### ✅ DO:
- Always use `--no-install-recommends` when installing packages
- Install minimal packages (vim, curl, wget, git, python3-minimal)
- Check `dpkg -l | grep "^iU"` for broken packages
- Use `apt clean` regularly to save space
- **Use Ubuntu 22.04 LTS** - most stable and tested

### ❌ DON'T:
- Install packages with services (ghostscript, cups, mysql-server, postgresql)
- Install desktop environments (gnome, kde, xfce)
- Install systemd-related packages
- Run services in proot (won't work)

## 💡 Tips & Tricks

### Speed up apt
```bash
# Disable apt-daily services
systemctl mask apt-daily.service apt-daily-upgrade.service
```

### Save disk space
```bash
# Clean cache
apt clean
apt autoclean
apt autoremove -y

# Remove docs and man pages (optional)
rm -rf /usr/share/doc/* /usr/share/man/*
```

### Backup and restore
```bash
# Backup rootfs (from host)
tar -czf fakeroot-backup.tar.gz -C ~/.fakeroot-proot .

# Restore
rm -rf ~/.fakeroot-proot
mkdir -p ~/.fakeroot-proot
tar -xzf fakeroot-backup.tar.gz -C ~/.fakeroot-proot
```

## 📚 Popular Packages

### Development
```bash
apt install -y --no-install-recommends \
  build-essential git curl wget \
  python3 python3-pip python3-venv \
  nodejs npm \
  golang-go \
  openjdk-11-jdk
```

### CLI Tools
```bash
apt install -y --no-install-recommends \
  vim nano tmux screen \
  htop ncdu tree \
  zip unzip \
  net-tools iputils-ping
```

---

<a name="tieng-viet"></a>
# 🇻🇳 Phiên Bản Tiếng Việt

## 🚀 Khởi động nhanh

```bash
# Cài đặt và khởi động
bash root.sh

# Cài đặt distro cụ thể
bash root.sh -i

# Cài lại từ đầu
bash root.sh -r

# Xóa rootfs
bash root.sh -u
```

## 📦 Cài đặt packages

### Ubuntu/Debian (⭐ Ubuntu 22.04 Khuyến nghị)
```bash
# Cách ĐÚNG (tránh lỗi dpkg)
apt install -y --no-install-recommends <package>

# Ví dụ
apt update
apt install -y --no-install-recommends vim curl wget git python3 nodejs

# Tránh cài các packages này (thường lỗi trong proot)
# ❌ ghostscript, cups, avahi-daemon, systemd-related packages
```

### Alpine Linux
```bash
apk update
apk add vim curl wget git python3 nodejs
```

### Arch Linux
```bash
pacman -Syu
pacman -S vim curl wget git python3 nodejs
```

## 🔧 Fix lỗi thường gặp

### Lỗi GPG "NO_PUBKEY"
```bash
# Cách 1: Dùng script có sẵn
fix-apt-keys

# Cách 2: Bypass GPG
apt update --allow-insecure-repositories
apt install -y --allow-unauthenticated <package>
```

### Lỗi DPKG "Sub-process /usr/bin/dpkg returned an error code (1)"
```bash
# Cách 1: Dùng script có sẵn
fix-dpkg-errors

# Cách 2: Fix thủ công
dpkg --configure -a
apt install -f -y
apt clean

# Cách 3: Xóa packages lỗi
dpkg --purge --force-all libpaper1 libgs9 ghostscript

# Cách 4: Luôn dùng --no-install-recommends
apt install -y --no-install-recommends <package>
```

### Lỗi SSL/Curl "certificate verify failed"
```bash
# Cách 1: Dùng script có sẵn
fix-ssl-certs
source ~/.bashrc

# Cách 2: Fix thủ công
apt install -y --no-install-recommends ca-certificates
update-ca-certificates --fresh

# Cách 3: Set biến môi trường
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
```

### Lỗi "systemctl: command not found"
```bash
# Đã có fake systemctl, nhưng nếu vẫn lỗi:
export PATH="/usr/local/bin:$PATH"
systemctl status test  # Sẽ không crash
```

## 🛠️ Tools có sẵn trong proot

```bash
fix-apt-keys        # Fix GPG keys
fix-dpkg-errors     # Fix dpkg errors
fix-ssl-certs       # Fix SSL/curl errors
systemctl           # Fake systemctl (không làm gì)
```

## 📝 Best Practices

### ✅ NÊN làm:
- Luôn dùng `--no-install-recommends` khi cài packages
- Cài minimal packages (vim, curl, wget, git, python3-minimal)
- Kiểm tra `dpkg -l | grep "^iU"` để xem packages lỗi
- Dùng `apt clean` thường xuyên để tiết kiệm dung lượng
- **Dùng Ubuntu 22.04 LTS** - ổn định và đã test kỹ nhất

### ❌ KHÔNG NÊN làm:
- Cài packages có services (ghostscript, cups, mysql-server, postgresql)
- Cài desktop environments (gnome, kde, xfce)
- Cài systemd-related packages
- Chạy services trong proot (không hoạt động)

## 🐛 Debug

### Kiểm tra trạng thái
```bash
# Kiểm tra packages lỗi
dpkg -l | grep "^iU\|^iF"

# Kiểm tra apt config
cat /etc/apt/apt.conf.d/99-proot-no-check

# Kiểm tra policy-rc.d
cat /usr/sbin/policy-rc.d

# Kiểm tra systemctl
which systemctl
systemctl --version
```

### Logs
```bash
# Apt logs
cat /var/log/apt/term.log
cat /var/log/apt/history.log

# Dpkg logs
cat /var/log/dpkg.log

# Xem lỗi chi tiết khi cài package
apt install -y --no-install-recommends <package> 2>&1 | tee install.log
```

## 💡 Tips & Tricks

### Tăng tốc apt
```bash
# Disable apt-daily services
systemctl mask apt-daily.service apt-daily-upgrade.service

# Dùng mirror gần
# Edit /etc/apt/sources.list và thay archive.ubuntu.com bằng mirror địa phương
```

### Tiết kiệm dung lượng
```bash
# Xóa cache
apt clean
apt autoclean

# Xóa packages không cần thiết
apt autoremove -y

# Xóa docs và man pages (optional)
rm -rf /usr/share/doc/* /usr/share/man/*
```

### Backup và restore
```bash
# Backup rootfs (từ host)
tar -czf fakeroot-backup.tar.gz -C ~/.fakeroot-proot .

# Restore
rm -rf ~/.fakeroot-proot
mkdir -p ~/.fakeroot-proot
tar -xzf fakeroot-backup.tar.gz -C ~/.fakeroot-proot
```

## 🔐 Bảo mật

⚠️ **LƯU Ý**: Proot không phải là security boundary!

- Không dùng cho production
- Không lưu sensitive data
- Không chạy untrusted code
- GPG verification đã bị disable để tránh lỗi

## 📚 Packages phổ biến

### Development
```bash
apt install -y --no-install-recommends \
  build-essential git curl wget \
  python3 python3-pip python3-venv \
  nodejs npm \
  golang-go \
  openjdk-11-jdk
```

### CLI Tools
```bash
apt install -y --no-install-recommends \
  vim nano tmux screen \
  htop ncdu tree \
  zip unzip \
  net-tools iputils-ping
```

### Python Development
```bash
apt install -y --no-install-recommends \
  python3-minimal python3-pip python3-venv \
  python3-dev python3-setuptools

# Tạo venv
python3 -m venv ~/venv
source ~/venv/bin/activate
```

## 🆘 Help

```bash
# Trong proot
fix-apt-keys --help
fix-dpkg-errors --help

# Từ host
bash root.sh --help

# Xem docs
cat /home/red/Documents/FIX_GPG_ERRORS.md
```

## 🔗 Links

- Script: `/home/red/Documents/root.sh`
- Docs: `/home/red/Documents/FIX_GPG_ERRORS.md`
- Rootfs location: `~/.fakeroot-proot`
- Proot binary: `~/.local/bin/proot`
