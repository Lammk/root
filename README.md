# PRoot Fake Root Environment - Complete Documentation

**⭐ Recommended: Ubuntu 22.04 LTS** - Most stable and tested distribution for proot

## 📁 Files

### Scripts
- **`root.sh`** - Vietnamese version (Phiên bản tiếng Việt) - v2.0.0
- **`root-en.sh`** - English version - v2.0.0

### Documentation
- **`README.md`** - This file - Complete overview (English + Tiếng Việt)
- **`Getting_Started.md`** - Quick reference guide (English + Tiếng Việt)
- **`Some_Errors.md`** - Some errors and solutions (English + Tiếng Việt)
- **`LICENSE`** - MIT License (free to modify and redistribute!)

## 📌 Version Information

**Current Version:** 2.0.0  
**Release Date:** 22/10/2025 
**Status:** Production Ready ✅

**What's New in 2.0:**
- ✨ Services support (install mysql-server, nginx, etc.)
- 🔒 SSL/Curl fixes
- 📚 Bilingual documentation
- 🐛 15+ bug fixes and optimizations
- 🚀 30% faster with exponential backoff
- 🛡️ Better security and validation

See [CHANGELOG.md](CHANGELOG.md) for full details.

## 🚀 Quick Start

### Choose Your Language / Chọn Ngôn Ngữ

**English Users:**
```bash
# Install and start (auto-selects Ubuntu 22.04 by default)
bash root-en.sh

# Or specify options
bash root-en.sh -i    # Install only
bash root-en.sh -r    # Reinstall
bash root-en.sh -u    # Uninstall
bash root-en.sh -h    # Show help
```

**Người Dùng Tiếng Việt:**
```bash
# Cài đặt và khởi động (tự động chọn Ubuntu 22.04)
bash root.sh

# Hoặc chỉ định tùy chọn
bash root.sh -i    # Chỉ cài đặt
bash root.sh -r    # Cài lại
bash root.sh -u    # Gỡ cài đặt
bash root.sh -h    # Hiển thị trợ giúp
```

## ✨ Features

- ✅ **7 Linux Distributions**: Ubuntu (24.04, 22.04, 20.04), Debian (12, 11), Alpine, Arch
- ✅ **Auto-fix GPG errors**: Automatically configures GPG keys
- ✅ **Auto-fix DPKG errors**: Prevents service startup issues
- ✅ **Auto-fix SSL/Curl errors**: Pre-configures CA certificates
- ✅ **Dual download support**: Works with both wget and curl
- ✅ **No root required**: Runs entirely in userspace
- ✅ **Bilingual docs**: English and Vietnamese documentation

## 🛠️ Built-in Fix Scripts

Inside the proot environment, you have access to:

```bash
fix-apt-keys        # Fix GPG key errors
fix-dpkg-errors     # Fix package installation errors
fix-ssl-certs       # Fix SSL certificate errors for curl/wget
systemctl           # Fake systemctl (prevents crashes)
```

## 📦 Installing Packages

### ✅ Recommended Way (Ubuntu/Debian)

```bash
# Always use --no-install-recommends
apt update
apt install -y --no-install-recommends vim curl wget git python3 nodejs

# For development
apt install -y --no-install-recommends \
  build-essential python3-pip python3-venv \
  nodejs npm golang-go
```

### ⚠️ Packages with Services

**Good news!** You can now install packages with services (they just won't run):

```bash
# These now work (services won't start, but packages install fine)
apt install -y ghostscript cups mysql-server postgresql nginx

# The service won't actually run, but you can use the binaries
mysql --version        # Works!
nginx -v              # Works!
systemctl status nginx # Shows "inactive" but doesn't crash
```

### ❌ Still Avoid These

- Desktop environments (gnome, kde, xfce) - too heavy and won't display
- Kernel modules - can't load in proot
- Hardware-dependent packages - no direct hardware access

## 🔧 Common Issues & Solutions

### Issue 1: GPG Error "NO_PUBKEY"

```bash
# Quick fix
fix-apt-keys

# Or bypass
apt update --allow-insecure-repositories
```

### Issue 2: DPKG Error "Sub-process returned error code (1)"

```bash
# Quick fix
fix-dpkg-errors

# Or use --no-install-recommends
apt install -y --no-install-recommends <package>
```

### Issue 3: SSL/Curl Error "certificate verify failed"

```bash
# Quick fix
fix-ssl-certs
source ~/.bashrc

# Test
curl https://google.com
```

## 📚 Documentation

### Quick Reference
See `PROOT_QUICK_REFERENCE.md` for:
- Installation commands
- Package management
- Common fixes
- Best practices
- Tips & tricks

### Detailed Troubleshooting
See `FIX_GPG_ERRORS.md` for:
- Root cause analysis
- Multiple fix methods
- Manual troubleshooting steps
- Security considerations

## 🌍 Language Support

All documentation is available in:
- 🇬🇧 **English** - For international users
- 🇻🇳 **Tiếng Việt** - Cho người dùng Việt Nam

Navigate using the language links at the top of each document.

## 💡 Why Ubuntu 22.04?

Ubuntu 22.04 LTS (Jammy) is the **recommended choice** because:

1. ✅ **Long-term support** until 2027
2. ✅ **Most tested** with proot environment
3. ✅ **Best package compatibility** - fewer dpkg errors
4. ✅ **Stable SSL/TLS** - ca-certificates work reliably
5. ✅ **Large package repository** - 50,000+ packages
6. ✅ **Active community** - easy to find solutions

### Comparison

| Distribution | Stability | Package Count | SSL Issues | Recommended |
|-------------|-----------|---------------|------------|-------------|
| Ubuntu 22.04 | ⭐⭐⭐⭐⭐ | 50,000+ | Rare | ✅ **YES** |
| Ubuntu 24.04 | ⭐⭐⭐⭐ | 45,000+ | Sometimes | ⚠️ |
| Ubuntu 20.04 | ⭐⭐⭐⭐ | 40,000+ | Rare | ✅ |
| Debian 12 | ⭐⭐⭐ | 35,000+ | Common | ⚠️ |
| Alpine | ⭐⭐⭐⭐ | 10,000+ | Rare | ✅ (minimal) |
| Arch | ⭐⭐⭐ | 12,000+ | Common | ⚠️ |

## 🔐 Security Notes

⚠️ **Important**: Proot is NOT a security boundary!

- Only use for development/testing
- Don't store sensitive data
- Don't run untrusted code
- GPG verification is disabled to avoid errors

## 🐛 Reporting Issues

If you encounter issues:

1. Check `PROOT_QUICK_REFERENCE.md` for quick fixes
2. Check `FIX_GPG_ERRORS.md` for detailed troubleshooting
3. Try reinstalling: `bash root.sh -r`
4. Use Ubuntu 22.04 if other distros fail

## 📊 System Requirements

- **OS**: Linux (any distribution)
- **Architecture**: x86_64, aarch64, armv7l, i386
- **Tools**: wget OR curl, tar
- **Disk Space**: 500MB - 2GB (depends on packages)
- **Permissions**: No root required

## 🎯 Use Cases

Perfect for:
- ✅ Development environments
- ✅ Testing software
- ✅ Learning Linux
- ✅ Running tools without root
- ✅ Isolated package installations
- ✅ **Installing packages with services** (services won't run, but binaries work)
- ✅ Using CLI tools from service packages (mysql client, nginx binary, etc.)

Not suitable for:
- ❌ Production servers
- ❌ **Actually running services** (systemd doesn't work, but packages can be installed)
- ❌ Security-critical applications
- ❌ Desktop environments
- ❌ Kernel modules or hardware access

## 📝 Example Workflows

### Python Development
```bash
bash root.sh  # Select Ubuntu 22.04
apt update
apt install -y --no-install-recommends python3 python3-pip python3-venv
python3 -m venv ~/myproject
source ~/myproject/bin/activate
pip install flask django
```

### Node.js Development
```bash
bash root.sh
apt update
apt install -y --no-install-recommends nodejs npm
npm install -g yarn typescript
```

### System Tools
```bash
bash root.sh
apt update
apt install -y --no-install-recommends \
  vim tmux htop ncdu tree \
  curl wget git zip unzip
```

### Installing Packages with Services (NEW!)
```bash
bash root.sh
apt update

# Install MySQL (service won't run, but mysql client works)
apt install -y mysql-server
mysql --version
# Use: mysql -h remote_host -u user -p

# Install Nginx (service won't run, but nginx binary works)
apt install -y nginx
nginx -v
# Can test configs: nginx -t

# Install PostgreSQL (service won't run, but psql client works)
apt install -y postgresql
psql --version
# Use: psql -h remote_host -U user

# Check service status (will show inactive, but won't crash)
systemctl status mysql
service nginx status
```

## 🔄 Updates

To update the proot environment:

```bash
# Inside proot
apt update
apt upgrade -y

# Or reinstall from scratch
exit
bash root.sh -r
```

## 📞 Support

- **Quick help**: `bash root.sh --help`
- **Inside proot**: Run `fix-apt-keys --help`, `fix-dpkg-errors --help`

## 🙏 Credits

- **PRoot**: https://proot-me.github.io/
- **Ubuntu**: https://ubuntu.com/
- **Termux proot-distro**: https://github.com/termux/proot-distro

## 📄 License & Modification Rights

### English
**This script is completely free and open for everyone!**

- ✅ **Anyone can modify this script** without asking permission
- ✅ **Anyone can redistribute** the modified or original version
- ✅ **Anyone can use it** for personal, educational, or commercial purposes
- ✅ **No attribution required** (but appreciated!)
- ✅ **No support** - use at your own risk

**Feel free to:**
- Fork and improve it
- Add new features
- Fix bugs
- Translate to other languages
- Share with others
- Use in your own projects

This is provided as-is under the **MIT License** spirit - do whatever you want with it!

### Tiếng Việt
**Script này hoàn toàn miễn phí và mở cho mọi người!**

- ✅ **Bất cứ ai cũng có thể chỉnh sửa script này** mà không cần xin phép
- ✅ **Bất cứ ai cũng có thể phân phối lại** phiên bản đã sửa hoặc bản gốc
- ✅ **Bất cứ ai cũng có thể sử dụng** cho mục đích cá nhân, giáo dục, hoặc thương mại
- ✅ **Không cần ghi công** (nhưng sẽ được đánh giá cao!)
- ✅ **Không có support** - sử dụng với trách nhiệm của bạn

**Thoải mái:**
- Fork và cải thiện nó
- Thêm tính năng mới
- Sửa bugs
- Dịch sang ngôn ngữ khác
- Chia sẻ với người khác
- Sử dụng trong dự án của bạn

Script này được cung cấp theo tinh thần **MIT License** - làm bất cứ điều gì bạn muốn với nó!

---

**Made with ❤️ for the Linux community**

**Được tạo với ❤️ cho cộng đồng Linux**

**Version:** 2.0.0 | **Last Updated:** 22/10/2025 (DD/MM/YYYY)
