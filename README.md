# PRoot Fake Root Environment - Complete Documentation

**⭐ Recommended: Ubuntu 22.04 LTS** - Most stable and tested distribution for proot

## 📁 Files

- **`root.sh`** - Main installation and management script
- **`PROOT_QUICK_REFERENCE.md`** - Quick reference guide (English + Tiếng Việt)
- **`FIX_GPG_ERRORS.md`** - Detailed troubleshooting guide (English + Tiếng Việt)
- **`README.md`** - This file

## 🚀 Quick Start

```bash
# Install and start (auto-selects Ubuntu 22.04 by default)
bash root.sh

# Or specify options
bash root.sh -i    # Install only
bash root.sh -r    # Reinstall
bash root.sh -u    # Uninstall
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

### ❌ Avoid These Packages

These packages often fail in proot:
- ghostscript, cups, avahi-daemon
- mysql-server, postgresql
- systemd-related packages
- Desktop environments (gnome, kde, xfce)

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

Not suitable for:
- ❌ Production servers
- ❌ Running services (systemd doesn't work)
- ❌ Security-critical applications
- ❌ Desktop environments

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
- **Documentation**: Read the MD files in `/home/red/Documents/`

## 🙏 Credits

- **PRoot**: https://proot-me.github.io/
- **Ubuntu**: https://ubuntu.com/
- **Termux proot-distro**: https://github.com/termux/proot-distro

## 📄 License

This script is provided as-is for educational and development purposes.

---

**Made with ❤️ for the Linux community**

**Được tạo với ❤️ cho cộng đồng Linux**
