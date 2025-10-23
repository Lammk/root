#!/usr/bin/env bash
# Ubuntu 22.04 VM with QEMU - Auto Login Terminal
# Modified from: quanvm0501 (BlackCatOfficial), BiraloGaming
# RAM: 8GB, Storage: 40GB, CPU: 2 cores

# Don't use set -e to prevent QEMU from killing itself on minor errors
set -uo pipefail

# =============================
# CẤU HÌNH
# =============================
VM_NAME="ubuntu-22.04"
VM_DIR="$HOME/VMs/$VM_NAME"
IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMG_FILE="$VM_DIR/ubuntu-base.img"
PERSISTENT_DISK="$VM_DIR/persistent.qcow2"
SEED_FILE="$VM_DIR/seed.iso"

# VM Specs
RAM="8G"
CPU_CORES="2"
DISK_SIZE="40G"
PERSISTENT_SIZE="20G"
SSH_PORT="2222"

# Credentials
HOSTNAME="ubuntu-vm"
USERNAME="ubuntu"
PASSWORD="ubuntu"

# Swap (set to 0G if using KVM)
SWAP_SIZE="2G"

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
║      Modified from: quanvm0501, BiraloGaming         ║
║                                                      ║
╚══════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
}

check_tools() {
    print_info "Checking required tools..."
    local missing=0
    
    for cmd in qemu-system-x86_64 qemu-img cloud-localds wget; do
        if ! command -v $cmd &>/dev/null; then
            print_error "Required command '$cmd' not found"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        echo ""
        echo "Install required packages:"
        echo "  Ubuntu/Debian: sudo apt install qemu-system-x86 qemu-utils cloud-image-utils wget"
        echo "  Fedora:        sudo dnf install qemu-system-x86 cloud-utils wget"
        echo "  Arch:          sudo pacman -S qemu-full cloud-init wget"
        exit 1
    fi
    
    print_info "All required tools found ✓"
}

check_resources() {
    print_info "Checking system resources..."
    
    # Create VM dir if not exists
    mkdir -p "$VM_DIR" 2>/dev/null || true
    
    # Check available RAM
    local total_ram=$(free -g | awk '/^Mem:/{print $2}')
    local vm_ram=$(echo "$RAM" | sed 's/G//')
    
    if [ "$total_ram" -lt "$((vm_ram + 2))" ]; then
        print_warn "Low RAM: Host has ${total_ram}G, VM needs ${vm_ram}G"
        print_warn "Recommended: At least $((vm_ram + 2))G total RAM"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
    
    # Check disk space
    local free_space=$(df -BG "$VM_DIR" 2>/dev/null | awk 'NR==2{print $4}' | sed 's/G//' || echo "100")
    if [ "$free_space" -lt 50 ]; then
        print_warn "Low disk space: ${free_space}G available"
        print_warn "Recommended: At least 50G free space"
    fi
    
    # Check if another VM is running
    if pgrep -f "qemu-system-x86_64.*$VM_NAME" &>/dev/null; then
        print_error "VM is already running!"
        print_error "PID: $(pgrep -f "qemu-system-x86_64.*$VM_NAME")"
        print_error "Stop it first: ./ubuntu-vm.sh -k"
        exit 1
    fi
    
    # Validate image files (only if exists)
    if [ -f "$IMG_FILE" ]; then
        print_info "Validating disk image..."
        if ! qemu-img check "$IMG_FILE" &>/dev/null; then
            print_warn "Image file may be corrupted: $IMG_FILE"
            print_warn "Consider recreating the VM"
        fi
    fi
    
    print_info "Resource check passed ✓"
}

check_kvm() {
    if [ -r /dev/kvm ]; then
        print_info "KVM acceleration available ✓"
        # CPU host passthrough with safe features (compatible with most CPUs)
        # Removed potentially unsupported features to prevent crashes
        KVM_FLAG="-enable-kvm -cpu host"
    else
        print_warn "KVM not available, using TCG (slower)"
        print_warn "To enable KVM: sudo modprobe kvm-intel (or kvm-amd)"
        KVM_FLAG="-accel tcg"
    fi
}

setup_vm() {
    print_info "Setting up VM..."
    mkdir -p "$VM_DIR"
    cd "$VM_DIR"
    
    # Download cloud image if not exists
    if [ ! -f "$IMG_FILE" ]; then
        print_info "Downloading Ubuntu 22.04 Cloud Image..."
        wget "$IMG_URL" -O "$IMG_FILE" --show-progress
        
        print_info "Resizing image to $DISK_SIZE..."
        qemu-img resize "$IMG_FILE" "$DISK_SIZE"
        
        print_info "Creating cloud-init configuration..."
        
        # Create user-data for cloud-init
        cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
manage_etc_hosts: true
disable_root: false
ssh_pwauth: true
chpasswd:
  list: |
    $USERNAME:$PASSWORD
  expire: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
packages:
  - openssh-server
runcmd:
  - echo "$USERNAME:$PASSWORD" | chpasswd
  - mkdir -p /var/run/sshd
  - systemctl enable ssh
  - systemctl start ssh
  # Swap file creation
  - |
    SWAP_SIZE="$SWAP_SIZE"
    if [ "\$SWAP_SIZE" != "0G" ] && [ -n "\$SWAP_SIZE" ]; then
      fallocate -l \$SWAP_SIZE /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    fi
  # Auto-login on serial console
  - mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
  - |
    cat > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf <<AUTOLOGIN
    [Service]
    ExecStart=
    ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
    AUTOLOGIN
  - systemctl daemon-reload
  - systemctl restart serial-getty@ttyS0.service
  # Disable cloud-init after first boot for faster subsequent boots
  - touch /etc/cloud/cloud-init.disabled
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: false
resize_rootfs: true
EOF

        # Create meta-data
        cat > meta-data <<EOF
instance-id: iid-local01
local-hostname: $HOSTNAME
EOF

        # Generate seed ISO
        print_info "Generating cloud-init seed ISO..."
        cloud-localds "$SEED_FILE" user-data meta-data
        
        print_info "VM image setup complete!"
    else
        print_info "VM image already exists, skipping download"
    fi
    
    # Create persistent disk if not exists
    if [ ! -f "$PERSISTENT_DISK" ]; then
        print_info "Creating persistent disk ($PERSISTENT_SIZE)..."
        qemu-img create -f qcow2 "$PERSISTENT_DISK" "$PERSISTENT_SIZE"
    fi
}

cleanup() {
    echo ""
    print_info "Shutting down VM gracefully..."
    # Send SIGTERM first for graceful shutdown
    pkill -TERM -f "qemu-system-x86_64.*$VM_NAME" 2>/dev/null || true
    sleep 2
    # Force kill if still running
    pkill -KILL -f "qemu-system-x86_64.*$VM_NAME" 2>/dev/null || true
    print_info "VM stopped"
}

start_vm() {
    if [ ! -f "$IMG_FILE" ]; then
        print_error "VM image not found. Run setup first."
        exit 1
    fi
    
    # Pre-flight checks
    check_resources
    
    trap cleanup SIGINT SIGTERM EXIT
    
    print_banner
    echo -e "${CYAN}CREDIT: quanvm0501 (BlackCatOfficial), BiraloGaming${RESET}"
    echo ""
    print_info "Starting Ubuntu 22.04 VM..."
    echo ""
    echo -e "${GREEN}Credentials:${RESET}"
    echo "  Username: $USERNAME"
    echo "  Password: $PASSWORD"
    echo "  SSH:      ssh -p $SSH_PORT $USERNAME@localhost"
    echo ""
    echo -e "${YELLOW}Terminal Controls:${RESET}"
    echo "  Exit QEMU: Ctrl+A, then X"
    echo "  Monitor:   Ctrl+A, then C"
    echo ""
    echo -e "${CYAN}VM will auto-login after boot...${RESET}"
    echo ""
    read -n1 -r -p "Press any key to start VM..."
    echo ""
    
    cd "$VM_DIR"
    
    # Create log file for debugging
    local LOG_FILE="$VM_DIR/qemu.log"
    
    exec qemu-system-x86_64 \
        $KVM_FLAG \
        -m "$RAM" \
        -smp "$CPU_CORES",cores="$CPU_CORES",threads=1,sockets=1 \
        -drive file="$IMG_FILE",format=qcow2,if=virtio,cache=unsafe,aio=native,discard=unmap \
        -drive file="$PERSISTENT_DISK",format=qcow2,if=virtio,cache=unsafe,aio=native,discard=unmap \
        -drive file="$SEED_FILE",format=raw,if=virtio,cache=unsafe \
        -boot order=c,menu=off,strict=on \
        -device virtio-net-pci,netdev=n0,mq=on,vectors=4 \
        -netdev user,id=n0,hostfwd=tcp::"$SSH_PORT"-:22 \
        -device virtio-balloon-pci,id=balloon0,deflate-on-oom=on \
        -nographic \
        -serial mon:stdio \
        -no-reboot \
        -no-shutdown \
        -rtc base=localtime,clock=host,driftfix=slew \
        -global kvm-pit.lost_tick_policy=discard \
        -no-hpet \
        -overcommit mem-lock=off \
        -msg timestamp=on \
        -D "$LOG_FILE" \
        -name "$VM_NAME",process="$VM_NAME"
}

start_vm_gui() {
    if [ ! -f "$IMG_FILE" ]; then
        print_error "VM image not found. Run setup first."
        exit 1
    fi
    
    trap cleanup SIGINT SIGTERM
    
    print_info "Starting Ubuntu 22.04 VM (GUI mode)..."
    
    cd "$VM_DIR"
    
    # Create log file for debugging
    local LOG_FILE="$VM_DIR/qemu.log"
    
    exec qemu-system-x86_64 \
        $KVM_FLAG \
        -m "$RAM" \
        -smp "$CPU_CORES",cores="$CPU_CORES",threads=1,sockets=1 \
        -drive file="$IMG_FILE",format=qcow2,if=virtio,cache=unsafe,aio=native,discard=unmap \
        -drive file="$PERSISTENT_DISK",format=qcow2,if=virtio,cache=unsafe,aio=native,discard=unmap \
        -drive file="$SEED_FILE",format=raw,if=virtio,cache=unsafe \
        -boot order=c,menu=off,strict=on \
        -device virtio-net-pci,netdev=n0,mq=on,vectors=4 \
        -netdev user,id=n0,hostfwd=tcp::"$SSH_PORT"-:22 \
        -device virtio-balloon-pci,id=balloon0,deflate-on-oom=on \
        -vga virtio \
        -display gtk \
        -no-reboot \
        -no-shutdown \
        -rtc base=localtime,clock=host,driftfix=slew \
        -global kvm-pit.lost_tick_policy=discard \
        -no-hpet \
        -overcommit mem-lock=off \
        -msg timestamp=on \
        -D "$LOG_FILE" \
        -name "$VM_NAME",process="$VM_NAME"
}

vm_info() {
    echo -e "${CYAN}VM Information:${RESET}"
    echo "  Name:       $VM_NAME"
    echo "  RAM:        $RAM"
    echo "  CPU:        $CPU_CORES cores"
    echo "  Storage:    $DISK_SIZE"
    echo "  Username:   $USERNAME"
    echo "  Password:   $PASSWORD"
    echo "  SSH:        ssh -p $SSH_PORT $USERNAME@localhost"
    echo ""
    
    if [ -f "$IMG_FILE" ]; then
        echo -e "${CYAN}Disk Info:${RESET}"
        qemu-img info "$IMG_FILE" | grep -E "virtual size|disk size|format"
    fi
    
    echo ""
    if pgrep -f "qemu-system-x86_64.*$VM_NAME" &>/dev/null; then
        echo -e "${GREEN}Status: RUNNING${RESET}"
        echo "PID: $(pgrep -f "qemu-system-x86_64.*$VM_NAME")"
    else
        echo -e "${YELLOW}Status: STOPPED${RESET}"
    fi
}

stop_vm() {
    print_info "Stopping VM..."
    pkill -f "qemu-system-x86_64.*$VM_NAME" || print_warn "VM not running"
}

show_help() {
    cat << EOF
${CYAN}Ubuntu 22.04 VM Manager${RESET}
Modified from: quanvm0501 (BlackCatOfficial), BiraloGaming

Usage: $0 [OPTION]

Options:
  (no option)   Setup and start VM in terminal (auto-login)
  -s, --start   Start VM with GUI
  -k, --stop    Stop VM
  -i, --info    Show VM information
  --help        Show this help

Examples:
  $0              # Setup and start VM (terminal, auto-login)
  $0 -s           # Start VM with GUI
  $0 -k           # Stop VM
  $0 -i           # Show info

Credentials:
  Username: $USERNAME
  Password: $PASSWORD
  SSH:      ssh -p $SSH_PORT $USERNAME@localhost

Terminal Controls:
  Exit:     Ctrl+A, then X
  Monitor:  Ctrl+A, then C

Features:
  ✓ Auto-login to terminal after boot
  ✓ Cloud-init auto-configuration
  ✓ SSH ready on port $SSH_PORT
  ✓ KVM acceleration (if available)
  ✓ No manual installation needed

Files:
  VM Dir:   $VM_DIR
  Image:    $IMG_FILE
  Disk:     $PERSISTENT_DISK
EOF
}

# =============================
# MAIN
# =============================
print_banner
check_tools
check_kvm

case "${1:-}" in
    -s|--start)
        start_vm_gui
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
        setup_vm
        start_vm
        ;;
    *)
        print_error "Invalid option: $1"
        echo "Run '$0 --help' for usage"
        exit 1
        ;;
esac
