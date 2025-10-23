#!/usr/bin/env bash
# Ubuntu 22.04 VM with QEMU
# RAM: 8GB, Storage: 40GB, CPU: 2 cores

set -euo pipefail

# =============================
# CẤU HÌNH
# =============================
VM_NAME="ubuntu-22.04"
VM_DIR="$HOME/VMs/$VM_NAME"
DISK_IMAGE="$VM_DIR/ubuntu.qcow2"
DISK_SIZE="40G"
RAM="8G"
CPU_CORES="2"
ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
ISO_FILE="$VM_DIR/ubuntu-22.04.5-live-server-amd64.iso"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# =============================
# FUNCTIONS
# =============================
print_info() {
    echo -e "${GREEN}[INFO]${RESET} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════╗
║                                                      ║
║           UBUNTU 22.04 VM WITH QEMU                  ║
║                                                      ║
║           RAM: 8GB | Storage: 40GB | CPU: 2          ║
║                                                      ║
╚══════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
}

check_qemu() {
    if ! command -v qemu-system-x86_64 &>/dev/null; then
        print_error "QEMU chưa được cài đặt!"
        echo ""
        echo "Cài đặt QEMU:"
        echo "  Ubuntu/Debian: sudo apt install qemu-system-x86 qemu-utils"
        echo "  Fedora:        sudo dnf install qemu-system-x86"
        echo "  Arch:          sudo pacman -S qemu-full"
        exit 1
    fi
    print_info "QEMU đã được cài đặt: $(qemu-system-x86_64 --version | head -1)"
}

check_kvm() {
    if [ -r /dev/kvm ]; then
        print_info "KVM acceleration available ✓"
        KVM_ENABLED="-enable-kvm"
    else
        print_warn "KVM không khả dụng, VM sẽ chạy chậm hơn"
        print_warn "Để enable KVM: sudo modprobe kvm-intel (hoặc kvm-amd)"
        KVM_ENABLED=""
    fi
}

setup_vm() {
    print_info "Đang thiết lập VM..."
    
    # Tạo thư mục
    mkdir -p "$VM_DIR"
    
    # Tạo disk image nếu chưa có
    if [ ! -f "$DISK_IMAGE" ]; then
        print_info "Tạo disk image $DISK_SIZE..."
        qemu-img create -f qcow2 "$DISK_IMAGE" "$DISK_SIZE"
    else
        print_info "Disk image đã tồn tại: $DISK_IMAGE"
    fi
    
    # Download ISO nếu chưa có
    if [ ! -f "$ISO_FILE" ]; then
        print_info "Đang tải Ubuntu 22.04 ISO..."
        if command -v wget &>/dev/null; then
            wget -O "$ISO_FILE" "$ISO_URL" --show-progress
        elif command -v curl &>/dev/null; then
            curl -L -o "$ISO_FILE" "$ISO_URL" --progress-bar
        else
            print_error "Cần wget hoặc curl để tải ISO"
            exit 1
        fi
    else
        print_info "ISO đã tồn tại: $ISO_FILE"
    fi
}

start_vm_install() {
    print_info "Khởi động VM để cài đặt Ubuntu..."
    echo ""
    print_warn "Sau khi cài đặt xong, tắt VM và chạy lại script với option -s để start"
    echo ""
    sleep 3
    
    qemu-system-x86_64 \
        $KVM_ENABLED \
        -m "$RAM" \
        -smp "$CPU_CORES" \
        -hda "$DISK_IMAGE" \
        -cdrom "$ISO_FILE" \
        -boot d \
        -net nic,model=virtio \
        -net user,hostfwd=tcp::2222-:22 \
        -vga virtio \
        -display gtk \
        -name "$VM_NAME"
}

start_vm() {
    if [ ! -f "$DISK_IMAGE" ]; then
        print_error "Disk image không tồn tại. Chạy script không có option để cài đặt."
        exit 1
    fi
    
    print_info "Khởi động VM Ubuntu 22.04..."
    echo ""
    print_info "SSH forwarding: localhost:2222 -> VM:22"
    print_info "Để SSH: ssh -p 2222 user@localhost"
    echo ""
    
    qemu-system-x86_64 \
        $KVM_ENABLED \
        -m "$RAM" \
        -smp "$CPU_CORES" \
        -hda "$DISK_IMAGE" \
        -net nic,model=virtio \
        -net user,hostfwd=tcp::2222-:22 \
        -vga virtio \
        -display gtk \
        -name "$VM_NAME"
}

start_vm_headless() {
    if [ ! -f "$DISK_IMAGE" ]; then
        print_error "Disk image không tồn tại. Chạy script không có option để cài đặt."
        exit 1
    fi
    
    print_info "Khởi động VM Ubuntu 22.04 (terminal mode)..."
    echo ""
    print_info "VM sẽ chạy trực tiếp trong terminal này"
    print_info "Để thoát: Ctrl+A, sau đó X"
    print_info "SSH forwarding: localhost:2222 -> VM:22"
    echo ""
    sleep 2
    
    qemu-system-x86_64 \
        $KVM_ENABLED \
        -m "$RAM" \
        -smp "$CPU_CORES" \
        -hda "$DISK_IMAGE" \
        -net nic,model=virtio \
        -net user,hostfwd=tcp::2222-:22 \
        -nographic \
        -serial mon:stdio \
        -name "$VM_NAME"
}

stop_vm() {
    print_info "Đang tắt VM..."
    pkill -f "$VM_NAME" || print_warn "VM không chạy"
}

vm_info() {
    echo -e "${CYAN}VM Information:${RESET}"
    echo "  Name:     $VM_NAME"
    echo "  RAM:      $RAM"
    echo "  CPU:      $CPU_CORES cores"
    echo "  Storage:  $DISK_SIZE"
    echo "  Disk:     $DISK_IMAGE"
    echo "  ISO:      $ISO_FILE"
    echo ""
    
    if [ -f "$DISK_IMAGE" ]; then
        echo -e "${CYAN}Disk Info:${RESET}"
        qemu-img info "$DISK_IMAGE"
    fi
    
    echo ""
    if pgrep -f "$VM_NAME" &>/dev/null; then
        echo -e "${GREEN}Status: RUNNING${RESET}"
        echo "PID: $(pgrep -f "$VM_NAME")"
    else
        echo -e "${YELLOW}Status: STOPPED${RESET}"
    fi
}

show_help() {
    cat << EOF
${CYAN}Ubuntu 22.04 VM Manager${RESET}

Usage: $0 [OPTION]

Options:
  (no option)   Cài đặt VM mới (nếu chưa có) hoặc start VM trong terminal
  -s, --start   Start VM với GUI
  -h, --headless Start VM trong terminal (nographic mode)
  -k, --stop    Tắt VM
  -i, --info    Hiển thị thông tin VM
  --help        Hiển thị help này

Examples:
  $0              # Cài đặt hoặc start VM trong terminal (mặc định)
  $0 -s           # Start VM với GUI
  $0 -h           # Start VM trong terminal
  $0 -k           # Tắt VM
  $0 -i           # Xem thông tin VM

Terminal Mode:
  Thoát: Ctrl+A, sau đó X
  SSH:   ssh -p 2222 user@localhost (từ terminal khác)

Notes:
  - Cần cài QEMU trước: sudo apt install qemu-system-x86 qemu-utils
  - Enable KVM để tăng tốc: sudo modprobe kvm-intel
  - Disk image: $DISK_IMAGE
  - ISO file: $ISO_FILE
EOF
}

# =============================
# MAIN
# =============================
print_banner
check_qemu
check_kvm

case "${1:-}" in
    -s|--start)
        start_vm
        ;;
    -h|--headless)
        start_vm_headless
        ;;
    -k|--stop)
        stop_vm
        ;;
    -i|--info)
        vm_info
        ;;
    --help)
        show_help
        ;;
    "")
        # Nếu chưa có disk image, cài đặt
        if [ ! -f "$DISK_IMAGE" ]; then
            setup_vm
            start_vm_install
        else
            # Nếu đã có, start VM headless (mặc định)
            start_vm_headless
        fi
        ;;
    *)
        print_error "Option không hợp lệ: $1"
        echo "Chạy '$0 --help' để xem hướng dẫn"
        exit 1
        ;;
esac