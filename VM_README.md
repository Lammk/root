# Ubuntu 22.04 VM with QEMU - Auto Login

Script tự động tạo và quản lý Ubuntu 22.04 VM với QEMU.  
**Modified from:** quanvm0501 (BlackCatOfficial), BiraloGaming

## 🔑 Default Credentials

- **Username:** `ubuntu`
- **Password:** `ubuntu`
- **SSH Port:** `2222` (localhost:2222 → VM:22)
- **Auto-login:** ✅ Tự động login sau khi boot

## 📋 Thông Số VM

- **OS:** Ubuntu 22.04 LTS Server (Cloud Image)
- **RAM:** 8GB
- **Storage:** 40GB (main) + 20GB (persistent)
- **CPU:** 2 cores
- **Network:** NAT with SSH forwarding (port 2222)
- **Setup:** Cloud-init (không cần cài đặt thủ công)

---

## 🚀 Quick Start

### 1. Cài Đặt Dependencies

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install qemu-system-x86 qemu-utils cloud-image-utils wget
```

**Fedora:**
```bash
sudo dnf install qemu-system-x86 cloud-utils wget
```

**Arch:**
```bash
sudo pacman -S qemu-full cloud-init wget
```

### 2. Enable KVM (Optional - Tăng Tốc)

```bash
# Intel CPU
sudo modprobe kvm-intel

# AMD CPU
sudo modprobe kvm-amd

# Kiểm tra
ls -l /dev/kvm
```

### 3. Chạy VM

```bash
chmod +x ubuntu-vm.sh
./ubuntu-vm.sh
```

**Lần đầu chạy:**
1. Script tự động tải Ubuntu 22.04 Cloud Image (~700MB)
2. Tạo cloud-init configuration
3. Boot VM và **TỰ ĐỘNG LOGIN** vào terminal
4. Không cần cài đặt thủ công!

---

## 📖 Sử Dụng

### Start VM (Terminal - Auto Login) - MẶC ĐỊNH

```bash
./ubuntu-vm.sh
```

**Sau khi boot (~30-60 giây):**
- VM tự động login với user `ubuntu`
- Console xuất hiện ngay trong terminal
- Không cần nhập username/password!

### Start VM (GUI)

```bash
./ubuntu-vm.sh -s
# hoặc
./ubuntu-vm.sh --start
```

### Stop VM

```bash
./ubuntu-vm.sh -k
# hoặc
./ubuntu-vm.sh --stop
```

### Xem Thông Tin VM

```bash
./ubuntu-vm.sh -i
# hoặc
./ubuntu-vm.sh --info
```

---

## 🌐 Network & Access

### Terminal Mode (Mặc Định - Auto Login)

```bash
./ubuntu-vm.sh
# Chờ boot (~30-60 giây)
# VM tự động login:
# 
# Ubuntu 22.04.5 LTS ubuntu-vm ttyS0
# 
# ubuntu@ubuntu-vm:~$ █
```

**Phím tắt:**
- **Thoát QEMU:** `Ctrl+A`, sau đó `X`
- **Switch monitor:** `Ctrl+A`, sau đó `C`
- **Help:** `Ctrl+A`, sau đó `H`

### SSH vào VM

```bash
# Từ terminal khác
ssh -p 2222 ubuntu@localhost

# Password: ubuntu (nếu cần)
```

**SSH Key (Optional):**
```bash
# Copy SSH key vào VM
ssh-copy-id -p 2222 ubuntu@localhost

# Login không cần password
ssh -p 2222 ubuntu@localhost
```

---

## ✨ Features

### ✅ Auto-Login
- Không cần nhập username/password khi boot
- Tự động login vào terminal
- Sẵn sàng sử dụng ngay

### ✅ Cloud-Init Auto-Setup
- Tự động tạo user ubuntu/ubuntu
- Tự động cài SSH server
- Tự động cấu hình network
- Tự động resize disk
- Tự động tạo swap (2GB)

### ✅ No Manual Installation
- Không cần cài Ubuntu thủ công
- Không cần trả lời câu hỏi setup
- Chạy script là xong!

### ✅ KVM Acceleration
- Tự động detect và enable KVM
- Fallback to TCG nếu không có KVM
- Tốc độ gần như native

---

## 📁 File Structure

```
~/VMs/ubuntu-22.04/
├── ubuntu-base.img          # Main disk (40GB)
├── persistent.qcow2         # Persistent storage (20GB)
├── seed.iso                 # Cloud-init config
├── user-data                # Cloud-init user data
└── meta-data                # Cloud-init metadata
```

---

## ⚙️ Cấu Hình

### Thay Đổi RAM/CPU/Storage

Sửa trong script `ubuntu-vm.sh`:

```bash
RAM="8G"           # Thay đổi RAM
CPU_CORES="2"      # Thay đổi CPU cores
DISK_SIZE="40G"    # Thay đổi main disk
PERSISTENT_SIZE="20G"  # Thay đổi persistent disk
```

### Thay Đổi Credentials

```bash
USERNAME="ubuntu"
PASSWORD="ubuntu"
```

### Disable Swap

```bash
SWAP_SIZE="0G"     # Không tạo swap
```

---

## 🔧 Troubleshooting

### VM Chạy Chậm

**Nguyên nhân:** KVM chưa enable

**Fix:**
```bash
# Kiểm tra CPU hỗ trợ virtualization
egrep -c '(vmx|svm)' /proc/cpuinfo
# Nếu > 0 thì OK

# Enable KVM
sudo modprobe kvm-intel  # Intel
sudo modprobe kvm-amd    # AMD

# Kiểm tra
ls -l /dev/kvm
```

### VM Không Auto-Login

**Nguyên nhân:** Cloud-init chưa chạy xong

**Fix:** Chờ thêm 1-2 phút sau khi boot. Lần đầu boot mất thời gian hơn.

### Không Kết Nối SSH

**Nguyên nhân:** SSH server chưa start

**Fix:** Chờ VM boot xong (~1-2 phút lần đầu), sau đó:
```bash
ssh -p 2222 ubuntu@localhost
```

### Permission Denied /dev/kvm

**Fix:**
```bash
sudo usermod -aG kvm $USER
# Logout và login lại
```

---

## 💡 Tips

### 1. Snapshot VM

```bash
# Stop VM trước
./ubuntu-vm.sh -k

# Tạo snapshot
qemu-img snapshot -c backup1 ~/VMs/ubuntu-22.04/ubuntu-base.img

# List snapshots
qemu-img snapshot -l ~/VMs/ubuntu-22.04/ubuntu-base.img

# Restore snapshot
qemu-img snapshot -a backup1 ~/VMs/ubuntu-22.04/ubuntu-base.img
```

### 2. Resize Disk

```bash
# Stop VM
./ubuntu-vm.sh -k

# Resize
qemu-img resize ~/VMs/ubuntu-22.04/ubuntu-base.img +20G

# Start VM và trong VM:
sudo growpart /dev/vda 1
sudo resize2fs /dev/vda1
```

### 3. Port Forwarding

Sửa trong script:
```bash
-netdev user,id=n0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80
```

### 4. Shared Folder

```bash
# Thêm vào QEMU command:
-virtfs local,path=/path/on/host,mount_tag=hostshare,security_model=passthrough,id=hostshare

# Trong VM:
sudo mkdir /mnt/shared
sudo mount -t 9p -o trans=virtio hostshare /mnt/shared
```

---

## 📊 So Sánh vs ISO Install

| Feature | Cloud Image (This Script) | ISO Install |
|---------|--------------------------|-------------|
| **Setup Time** | ~2 phút | ~15-30 phút |
| **Manual Steps** | 0 | 10+ |
| **Auto-login** | ✅ | ❌ |
| **Auto-config** | ✅ | ❌ |
| **Download Size** | ~700MB | ~2GB |
| **First Boot** | ~30 giây | ~5 phút |

---

## 🎯 Use Cases

Perfect cho:
- ✅ Development environments
- ✅ Testing software
- ✅ CI/CD runners
- ✅ Quick Ubuntu instances
- ✅ Learning Linux
- ✅ Automation scripts

---

## 📚 Resources

- **QEMU Docs:** https://www.qemu.org/docs/master/
- **Cloud Images:** https://cloud-images.ubuntu.com/
- **Cloud-init:** https://cloudinit.readthedocs.io/

---

## ✅ Quick Commands

```bash
# Start VM (auto-login)
./ubuntu-vm.sh

# Start with GUI
./ubuntu-vm.sh -s

# Stop VM
./ubuntu-vm.sh -k

# VM info
./ubuntu-vm.sh -i

# SSH vào VM
ssh -p 2222 ubuntu@localhost

# Trong VM (auto-login):
# - Đã login sẵn với user ubuntu
# - Có sudo không cần password
# - SSH server đã chạy
# - Network đã config
```

---

**Created:** 23/10/2025  
**Script:** ubuntu-vm.sh  
**Version:** 2.0.0  
**Credits:** Modified from quanvm0501 (BlackCatOfficial), BiraloGaming
