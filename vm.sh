#!/usr/bin/env bash
# Ubuntu 22.04 VM with QEMU - Auto Login Terminal
# Modified from: quanvm0501 (BlackCatOfficial), BiraloGaming
# RAM: 8GB, Storage: 20GB, CPU: 2 cores

# Don't use set -e to prevent QEMU from killing itself on minor errors
set -uo pipefail

# =============================
# CẤU HÌNH
# =============================
VM_NAME="ubuntu-22.04"
VM_BASE_DIR=""  # Will be set by select_disk_location
VM_DIR=""       # Will be set after disk selection
IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMG_FILE=""     # Will be set after disk selection
SEED_FILE=""    # Will be set after disk selection

# VM Specs
RAM="8G"
CPU_CORES="2"
DISK_SIZE="20G"
SSH_PORT="2222"

# I/O and stability settings
IO_THREADS="1"  # Number of I/O threads for disk operations

# Freeze detection settings
FREEZE_CHECK_INTERVAL="10"  # Seconds between freeze checks
FREEZE_THRESHOLD="3"  # Number of failed checks before declaring freeze
RECOVERY_ATTEMPTS="3"  # Number of recovery attempts before asking to reset
MONITOR_LOG=""  # Will be set after VM_DIR is defined

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
║           RAM: 8GB | Storage: 20GB | CPU: 2          ║
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

show_host_specs() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║          HOST SYSTEM SPECIFICATIONS                ║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    # CPU Info
    local cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    local cpu_cores=$(nproc)
    local cpu_threads=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
    echo -e "${GREEN}CPU:${RESET}"
    echo "  Model:   $cpu_model"
    echo "  Cores:   $cpu_cores physical cores"
    echo "  Threads: $cpu_threads logical processors"
    echo ""
    
    # RAM Info
    local total_ram=$(free -h | awk '/^Mem:/{print $2}')
    local used_ram=$(free -h | awk '/^Mem:/{print $3}')
    local free_ram=$(free -h | awk '/^Mem:/{print $4}')
    local available_ram=$(free -h | awk '/^Mem:/{print $7}')
    echo -e "${GREEN}RAM:${RESET}"
    echo "  Total:     $total_ram"
    echo "  Used:      $used_ram"
    echo "  Free:      $free_ram"
    echo "  Available: $available_ram"
    echo ""
    
    # Disk Info
    echo -e "${GREEN}DISKS:${RESET}"
    df -h | grep -E '^/dev/' | while read -r line; do
        local device=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local used=$(echo "$line" | awk '{print $3}')
        local avail=$(echo "$line" | awk '{print $4}')
        local use_pct=$(echo "$line" | awk '{print $5}')
        local mount=$(echo "$line" | awk '{print $6}')
        echo "  $device"
        echo "    Size:      $size"
        echo "    Used:      $used ($use_pct)"
        echo "    Available: $avail"
        echo "    Mount:     $mount"
        echo ""
    done
    
    # VM Requirements
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║          VM REQUIREMENTS                           ║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${YELLOW}This VM will use:${RESET}"
    echo "  RAM:     $RAM"
    echo "  CPU:     $CPU_CORES cores"
    echo "  Storage: $DISK_SIZE (will grow as needed)"
    echo ""
    
    # Check if resources are sufficient
    local total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    local vm_ram_gb=$(echo "$RAM" | sed 's/G//')
    local available_ram_gb=$(free -g | awk '/^Mem:/{print $7}')
    
    local warnings=0
    
    if [ "$available_ram_gb" -lt "$vm_ram_gb" ]; then
        echo -e "${RED}⚠ WARNING: Not enough available RAM!${RESET}"
        echo "  VM needs: ${vm_ram_gb}G"
        echo "  Available: ${available_ram_gb}G"
        warnings=$((warnings + 1))
    fi
    
    if [ "$cpu_cores" -lt "$CPU_CORES" ]; then
        echo -e "${RED}⚠ WARNING: Not enough CPU cores!${RESET}"
        echo "  VM needs: $CPU_CORES cores"
        echo "  Available: $cpu_cores cores"
        warnings=$((warnings + 1))
    fi
    
    # Check disk space for VM directory (only if VM_DIR is set)
    if [ -n "$VM_DIR" ]; then
        mkdir -p "$VM_DIR" 2>/dev/null || true
        local vm_disk_free=$(df -BG "$VM_DIR" 2>/dev/null | awk 'NR==2{print $4}' | sed 's/G//' || echo "100")
        local disk_needed=$(echo "$DISK_SIZE" | sed 's/G//')
    else
        # Use home directory as fallback for space check
        local vm_disk_free=$(df -BG "$HOME" 2>/dev/null | awk 'NR==2{print $4}' | sed 's/G//' || echo "100")
        local disk_needed=$(echo "$DISK_SIZE" | sed 's/G//')
    fi
    
    if [ "$vm_disk_free" -lt "$disk_needed" ]; then
        echo -e "${RED}⚠ WARNING: Not enough disk space!${RESET}"
        echo "  VM needs: ${disk_needed}G"
        if [ -n "$VM_DIR" ]; then
            echo "  Available: ${vm_disk_free}G in $VM_DIR"
        else
            echo "  Available: ${vm_disk_free}G in $HOME"
        fi
        warnings=$((warnings + 1))
    fi
    
    echo ""
    if [ $warnings -eq 0 ]; then
        echo -e "${GREEN}✓ All system requirements met!${RESET}"
    else
        echo -e "${RED}✗ $warnings warning(s) found!${RESET}"
    fi
    echo ""
    
    # Ask to continue
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Setup cancelled by user"
        exit 0
    fi
}

select_disk_location() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║          SELECT DISK FOR VM INSTALLATION           ║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    # Get list of mounted filesystems with available space
    local -a disks
    local -a mount_points
    local -a available_space
    local -a sizes
    local index=1
    local max_space=0
    local max_space_index=0
    
    # Parse filesystem output - use /proc/mounts for reliable device/mount mapping
    # Then get size info from df for each mount point
    while read -r device mount fstype options dump pass; do
        # Skip empty lines
        [ -z "$device" ] && continue
        
        # Only process real block devices
        [[ ! "$device" =~ ^/dev/ ]] && continue
        
        # Validate mount point is actually a directory
        [ ! -d "$mount" ] && continue
        
        # Skip special filesystems
        [[ "$mount" =~ ^/(boot|snap|sys|proc|dev|run|tmp) ]] && continue
        [[ "$mount" =~ /boot/efi$ ]] && continue
        
        # Get size info from df for this specific mount point
        local df_info=$(df -h "$mount" 2>/dev/null | tail -1)
        [ -z "$df_info" ] && continue
        
        local size=$(echo "$df_info" | awk '{print $2}')
        local used=$(echo "$df_info" | awk '{print $3}')
        local avail=$(echo "$df_info" | awk '{print $4}')
        local use_pct=$(echo "$df_info" | awk '{print $5}')
        
        # Skip if avail is 0 or dash (not available)
        [[ "$avail" == "0" ]] || [[ "$avail" == "-" ]] && continue
        
        # Validate fields
        [ -z "$device" ] || [ -z "$mount" ] || [ -z "$avail" ] && continue
        
        # Convert to GB for comparison (handle different units properly)
        local avail_gb=0
        if [[ "$avail" =~ ^[0-9.]+G$ ]]; then
            avail_gb=$(echo "$avail" | sed 's/G//' | sed 's/,/\./' | cut -d. -f1)
        elif [[ "$avail" =~ ^[0-9.]+M$ ]]; then
            avail_gb=0
        elif [[ "$avail" =~ ^[0-9.]+T$ ]]; then
            avail_gb=$(echo "$avail" | sed 's/T//' | sed 's/,/\./' | awk '{print int($1*1024)}')
        elif [[ "$avail" =~ ^[0-9.]+K$ ]]; then
            avail_gb=0
        else
            # Try to parse as number (no unit)
            if [[ "$avail" =~ ^[0-9]+$ ]]; then
                avail_gb=$((avail / 1024 / 1024 / 1024))
            else
                continue  # Skip invalid entries
            fi
        fi
        
        disks+=("$device")
        mount_points+=("$mount")
        available_space+=("$avail")
        sizes+=("$size")
        
        # Track disk with most space
        if [ "$avail_gb" -gt "$max_space" ]; then
            max_space=$avail_gb
            max_space_index=$index
        fi
        
        index=$((index + 1))
    done < /proc/mounts
    
    # Check if any disks found
    if [ "${#disks[@]}" -eq 0 ]; then
        print_error "No suitable disks found!"
        echo "Please ensure you have at least one mounted disk with write access."
        exit 1
    fi
    
    # Display options
    echo -e "${GREEN}Available disks:${RESET}"
    echo ""
    
    for i in "${!disks[@]}"; do
        local num=$((i + 1))
        local is_default=""
        if [ "$num" -eq "$max_space_index" ]; then
            is_default=" ${YELLOW}[DEFAULT - Most space]${RESET}"
        fi
        
        echo -e "  ${CYAN}[$num]${RESET} ${disks[$i]}"
        echo -e "      Mount:     ${mount_points[$i]}"
        echo -e "      Size:      ${sizes[$i]}"
        echo -e "      Available: ${available_space[$i]}$is_default"
        echo ""
    done
    
    echo -e "  ${CYAN}[0]${RESET} Exit"
    echo ""
    
    # Ask user to select
    while true; do
        echo -e "${YELLOW}Select disk number [0-${#disks[@]}]:${RESET}"
        echo -e "${YELLOW}(Press ENTER for default: disk #$max_space_index with most space)${RESET}"
        read -p "> " choice
        
        # Handle empty input (default)
        if [ -z "$choice" ]; then
            choice=$max_space_index
            print_info "Using default disk #$choice (most available space)"
            break
        fi
        
        # Handle exit
        if [ "$choice" = "0" ]; then
            print_info "Setup cancelled by user"
            exit 0
        fi
        
        # Validate input
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#disks[@]}" ]; then
            break
        else
            print_error "Invalid choice. Please enter a number between 0 and ${#disks[@]}"
        fi
    done
    
    # Set selected disk
    local selected_index=$((choice - 1))
    local selected_mount="${mount_points[$selected_index]}"
    local selected_device="${disks[$selected_index]}"
    local selected_avail="${available_space[$selected_index]}"
    
    # Validate mount point is actually a directory
    if [ ! -d "$selected_mount" ]; then
        print_error "Selected mount point is not a directory: $selected_mount"
        print_error "This is a bug in disk detection. Please report this."
        exit 1
    fi
    
    # Check write permission
    if [ ! -w "$selected_mount" ]; then
        print_error "No write permission on: $selected_mount"
        print_error "Please select a different disk or run with appropriate permissions."
        exit 1
    fi
    
    echo ""
    print_info "Selected disk: $selected_device"
    print_info "Mount point: $selected_mount"
    print_info "Available space: $selected_avail"
    
    # Set VM directories based on selection
    VM_BASE_DIR="$selected_mount/VMs"
    VM_DIR="$VM_BASE_DIR/$VM_NAME"
    IMG_FILE="$VM_DIR/ubuntu-base.img"
    SEED_FILE="$VM_DIR/seed.iso"
    MONITOR_LOG="$VM_DIR/monitor.log"
    
    # Check if enough space (handle different units properly)
    local avail_mb
    local avail_gb
    
    # Convert available space to MB for accurate comparison
    if [[ "$selected_avail" =~ G$ ]]; then
        avail_gb=$(echo "$selected_avail" | sed 's/G//' | cut -d. -f1)
        avail_mb=$(echo "$selected_avail" | sed 's/G//' | awk '{print int($1*1024)}')
    elif [[ "$selected_avail" =~ M$ ]]; then
        avail_gb=0
        avail_mb=$(echo "$selected_avail" | sed 's/M//' | cut -d. -f1)
    elif [[ "$selected_avail" =~ T$ ]]; then
        avail_gb=$(echo "$selected_avail" | sed 's/T//' | awk '{print int($1*1024)}')
        avail_mb=$(echo "$selected_avail" | sed 's/T//' | awk '{print int($1*1024*1024)}')
    else
        avail_gb=0
        avail_mb=0
    fi
    
    local needed_gb=$(echo "$DISK_SIZE" | sed 's/G//')
    
    # Critical warning: Less than 500MB available
    if [ "$avail_mb" -lt 500 ]; then
        echo ""
        echo -e "${RED}╔════════════════════════════════════════════════════╗${RESET}"
        echo -e "${RED}║              ⚠️  CRITICAL WARNING ⚠️                ║${RESET}"
        echo -e "${RED}╚════════════════════════════════════════════════════╝${RESET}"
        echo ""
        print_error "Host is running out of storage space!"
        echo -e "${RED}  Available: ${selected_avail} (< 500MB)${RESET}"
        echo -e "${RED}  VM needs: ${DISK_SIZE}${RESET}"
        echo ""
        echo -e "${YELLOW}Risks:${RESET}"
        echo "  - VM installation may fail"
        echo "  - System may become unstable"
        echo "  - Data corruption possible"
        echo "  - Host OS may crash"
        echo ""
        echo -e "${CYAN}Recommendations:${RESET}"
        echo "  1. Free up space on the disk"
        echo "  2. Choose a different disk with more space"
        echo "  3. Cancel and clean up unnecessary files"
        echo ""
        read -p "Do you REALLY want to continue? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Setup cancelled - Good choice!"
            exit 0
        fi
        print_warn "Continuing with critically low disk space..."
    # Standard warning: Not enough space for VM
    elif [ "$avail_gb" -lt "$needed_gb" ]; then
        echo ""
        print_warn "Warning: Selected disk may not have enough space!"
        print_warn "  Available: ${selected_avail}"
        print_warn "  VM needs: ${DISK_SIZE}"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Setup cancelled"
            exit 0
        fi
    fi
    
    echo ""
    print_info "VM will be installed to: $VM_DIR"
    echo ""
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
        # CPU host passthrough with safe features
        KVM_FLAG="-enable-kvm -cpu host,migratable=on"
        USE_KVM=true
    else
        print_warn "KVM not available, using TCG (software emulation)"
        print_warn "To enable KVM: sudo modprobe kvm-intel (or kvm-amd)"
        print_info "Applying TCG optimizations..."
        
        # TCG optimizations - FIXED: proper thread configuration
        # tb-size: Translation block cache size (larger = better for TCG)
        KVM_FLAG="-accel tcg,thread=multi,tb-size=1024"
        USE_KVM=false
        
        # Reduce RAM for TCG (less overhead)
        if [ "$RAM" = "8G" ]; then
            RAM="4G"
            print_info "Reduced RAM to 4G for TCG mode"
        fi
        
        # Keep 2 cores for TCG multi-threading (better than 1)
        # TCG can benefit from 2 threads
        print_info "Using 2 CPU cores for TCG multi-threading"
        
        # Enable SWAP for TCG mode (compensate for less RAM)
        SWAP_SIZE="4G"
        print_info "Enabled 4G SWAP for TCG mode"
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
    
    # TCG-specific optimizations
    local EXTRA_FLAGS=""
    if [ "$USE_KVM" = false ]; then
        print_info "Using TCG optimizations for better performance..."
        # Simpler network for TCG (no multi-queue)
        EXTRA_FLAGS="-device virtio-net-pci,netdev=n0"
    else
        # Full features for KVM
        EXTRA_FLAGS="-device virtio-net-pci,netdev=n0,mq=on,vectors=4"
    fi
    
    # CRITICAL FIX: cache=unsafe causes data corruption and freezes
    # Use cache=writeback with proper AIO for stability
    local CACHE_MODE="writeback"
    local AIO_MODE="native"  # native is faster and more stable than threads
    
    # For TCG, use threads AIO (native requires KVM)
    if [ "$USE_KVM" = false ]; then
        AIO_MODE="threads"
    fi
    
    exec qemu-system-x86_64 \
        $KVM_FLAG \
        -machine q35,accel=$([ "$USE_KVM" = true ] && echo "kvm" || echo "tcg"),kernel_irqchip=on \
        -m "$RAM" \
        -smp "$CPU_CORES",cores="$CPU_CORES",threads=1,sockets=1,maxcpus="$CPU_CORES" \
        -object iothread,id=io1 \
        -drive file="$IMG_FILE",format=qcow2,if=none,id=drive0,cache="$CACHE_MODE",aio="$AIO_MODE",discard=unmap \
        -device virtio-blk-pci,drive=drive0,iothread=io1,num-queues="$CPU_CORES" \
        -drive file="$SEED_FILE",format=raw,if=virtio,cache=none,readonly=on \
        -boot order=c,menu=off,strict=on \
        $EXTRA_FLAGS \
        -netdev user,id=n0,hostfwd=tcp::"$SSH_PORT"-:22,net=10.0.2.0/24,dhcpstart=10.0.2.15 \
        -device virtio-balloon-pci,id=balloon0,deflate-on-oom=on,free-page-reporting=on \
        -device virtio-rng-pci,rng=rng0 \
        -object rng-random,id=rng0,filename=/dev/urandom \
        -nographic \
        -serial mon:stdio \
        -no-reboot \
        -rtc base=localtime,clock=host,driftfix=slew \
        -global kvm-pit.lost_tick_policy=discard \
        -overcommit mem-lock=off \
        -overcommit cpu-pm=on \
        -msg timestamp=on \
        -D "$LOG_FILE" \
        -pidfile "$VM_DIR/qemu.pid" \
        -name "$VM_NAME",process="$VM_NAME",debug-threads=on
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
    
    # TCG-specific optimizations
    local EXTRA_FLAGS=""
    if [ "$USE_KVM" = false ]; then
        print_info "Using TCG optimizations for better performance..."
        # Simpler network for TCG (no multi-queue)
        EXTRA_FLAGS="-device virtio-net-pci,netdev=n0"
    else
        # Full features for KVM
        EXTRA_FLAGS="-device virtio-net-pci,netdev=n0,mq=on,vectors=4"
    fi
    
    # CRITICAL FIX: cache=unsafe causes data corruption and freezes
    local CACHE_MODE="writeback"
    local AIO_MODE="native"
    
    if [ "$USE_KVM" = false ]; then
        AIO_MODE="threads"
    fi
    
    exec qemu-system-x86_64 \
        $KVM_FLAG \
        -machine q35,accel=$([ "$USE_KVM" = true ] && echo "kvm" || echo "tcg"),kernel_irqchip=on \
        -m "$RAM" \
        -smp "$CPU_CORES",cores="$CPU_CORES",threads=1,sockets=1,maxcpus="$CPU_CORES" \
        -object iothread,id=io1 \
        -drive file="$IMG_FILE",format=qcow2,if=none,id=drive0,cache="$CACHE_MODE",aio="$AIO_MODE",discard=unmap \
        -device virtio-blk-pci,drive=drive0,iothread=io1,num-queues="$CPU_CORES" \
        -drive file="$SEED_FILE",format=raw,if=virtio,cache=none,readonly=on \
        -boot order=c,menu=off,strict=on \
        $EXTRA_FLAGS \
        -netdev user,id=n0,hostfwd=tcp::"$SSH_PORT"-:22,net=10.0.2.0/24,dhcpstart=10.0.2.15 \
        -device virtio-balloon-pci,id=balloon0,deflate-on-oom=on,free-page-reporting=on \
        -device virtio-rng-pci,rng=rng0 \
        -object rng-random,id=rng0,filename=/dev/urandom \
        -vga virtio \
        -display gtk,gl=on \
        -no-reboot \
        -rtc base=localtime,clock=host,driftfix=slew \
        -global kvm-pit.lost_tick_policy=discard \
        -overcommit mem-lock=off \
        -overcommit cpu-pm=on \
        -msg timestamp=on \
        -D "$LOG_FILE" \
        -pidfile "$VM_DIR/qemu.pid" \
        -name "$VM_NAME",process="$VM_NAME",debug-threads=on
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
    
    # Stop monitor if running
    if [ -f "$VM_DIR/monitor.pid" ]; then
        local monitor_pid=$(cat "$VM_DIR/monitor.pid")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            kill "$monitor_pid" 2>/dev/null
            print_info "Stopped freeze monitor (PID: $monitor_pid)"
        fi
        rm -f "$VM_DIR/monitor.pid"
    fi
    
    pkill -f "qemu-system-x86_64.*$VM_NAME" || print_warn "VM not running"
}

find_vm_directory() {
    local require_exists="${1:-true}"
    
    # Find VM directory
    local found_vm_dir=""
    if [ -d "$HOME/VMs/$VM_NAME" ]; then
        found_vm_dir="$HOME/VMs/$VM_NAME"
    else
        # Search in all mounted disks - use null delimiter for safety
        while IFS= read -r -d '' mount; do
            if [ -d "$mount/VMs/$VM_NAME" ]; then
                found_vm_dir="$mount/VMs/$VM_NAME"
                break
            fi
        done < <(df --output=target | tail -n +2 | grep -v '^/boot' | grep -v '^/snap' | tr '\n' '\0')
    fi
    
    if [ -z "$found_vm_dir" ] && [ "$require_exists" = "true" ]; then
        print_error "VM not found!"
        echo "Searched locations:"
        echo "  - $HOME/VMs/$VM_NAME"
        echo "  - All mounted disks under /VMs/$VM_NAME"
        return 1
    fi
    
    echo "$found_vm_dir"
    return 0
}

setup_vm_paths() {
    # Helper function to set VM paths after finding directory
    if [ -n "$VM_DIR" ]; then
        IMG_FILE="$VM_DIR/ubuntu-base.img"
        SEED_FILE="$VM_DIR/seed.iso"
        MONITOR_LOG="$VM_DIR/monitor.log"
    fi
}

remove_vm() {
    local create_backup=true
    
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}║              ⚠️  DELETE VM WARNING ⚠️               ║${RESET}"
    echo -e "${RED}╚════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    VM_DIR=$(find_vm_directory)
    
    # Show VM info
    echo -e "${YELLOW}VM to be deleted:${RESET}"
    echo "  Location: $VM_DIR"
    if [ -f "$VM_DIR/ubuntu-base.img" ]; then
        local vm_size=$(du -sh "$VM_DIR" 2>/dev/null | awk '{print $1}')
        echo "  Size:     $vm_size"
    fi
    echo ""
    
    # Check if VM is running
    if pgrep -f "qemu-system-x86_64.*$VM_NAME" &>/dev/null; then
        print_warn "VM is currently RUNNING!"
        echo ""
        read -p "Stop VM before deleting? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            stop_vm
            sleep 2
        else
            print_error "Cannot delete running VM. Please stop it first."
            exit 1
        fi
    fi
    
    # Confirmation
    echo -e "${RED}This will permanently delete:${RESET}"
    echo "  - All VM files and data"
    echo "  - Ubuntu system image"
    echo "  - All installed packages"
    echo "  - All user files and configurations"
    echo "  - Monitor logs"
    echo ""
    if [ "$create_backup" = true ]; then
        echo -e "${GREEN}A backup will be created before deletion${RESET}"
    else
        echo -e "${RED}NO BACKUP will be created!${RESET}"
    fi
    echo ""
    
    read -p "Are you sure you want to delete this VM? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        
        # Create backup if requested
        local backup_dir=""
        if [ "$create_backup" = true ]; then
            print_info "Creating backup before deletion..."
            backup_dir="$VM_DIR.backup.$(date +%s)"
            
            # Check if we have write permission in parent directory
            local parent_dir=$(dirname "$VM_DIR")
            if [ ! -w "$parent_dir" ]; then
                print_error "No write permission in $parent_dir"
                print_error "Cannot create backup. Aborting deletion."
                exit 1
            fi
            
            # Check if enough space for backup
            local vm_size=$(du -sb "$VM_DIR" 2>/dev/null | awk '{print $1}')
            local avail_space=$(df -B1 "$parent_dir" 2>/dev/null | awk 'NR==2{print $4}')
            if [ "$vm_size" -gt "$avail_space" ]; then
                print_error "Not enough space for backup!"
                print_error "  VM size: $(numfmt --to=iec $vm_size)"
                print_error "  Available: $(numfmt --to=iec $avail_space)"
                read -p "Continue WITHOUT backup? (y/N): " -n 1 -r
                echo ""
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    print_info "Deletion cancelled"
                    exit 0
                fi
                backup_dir=""
            else
                # Attempt backup
                if cp -r "$VM_DIR" "$backup_dir" 2>&1 | tee /tmp/backup_error.log; then
                    # Verify backup
                    if [ -d "$backup_dir" ] && [ "$(ls -A "$backup_dir")" ]; then
                        print_info "Backup created: $backup_dir"
                    else
                        print_error "Backup verification failed!"
                        cat /tmp/backup_error.log
                        read -p "Continue WITHOUT backup? (y/N): " -n 1 -r
                        echo ""
                        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                            print_info "Deletion cancelled"
                            rm -rf "$backup_dir" 2>/dev/null
                            exit 0
                        fi
                        backup_dir=""
                    fi
                else
                    print_error "Backup failed!"
                    cat /tmp/backup_error.log
                    read -p "Continue WITHOUT backup? (y/N): " -n 1 -r
                    echo ""
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        print_info "Deletion cancelled"
                        exit 0
                    fi
                    backup_dir=""
                fi
                rm -f /tmp/backup_error.log
            fi
            echo ""
        fi
        
        print_info "Deleting VM..."
        
        # Delete VM directory
        if rm -rf "$VM_DIR"; then
            echo ""
            echo -e "${GREEN}╔════════════════════════════════════════════════════╗${RESET}"
            echo -e "${GREEN}║              VM DELETED SUCCESSFULLY               ║${RESET}"
            echo -e "${GREEN}╚════════════════════════════════════════════════════╝${RESET}"
            echo ""
            print_info "VM deleted: $VM_DIR"
            if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
                print_info "Backup available: $backup_dir"
                echo ""
                echo -e "${CYAN}To restore from backup:${RESET}"
                echo "  mv \"$backup_dir\" \"$VM_DIR\""
            fi
        else
            print_error "Failed to delete VM directory"
            exit 1
        fi
    else
        print_info "Deletion cancelled"
        exit 0
    fi
}

remove_vm_no_backup() {
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}║        ⚠️  DELETE VM WITHOUT BACKUP ⚠️              ║${RESET}"
    echo -e "${RED}╚════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    VM_DIR=$(find_vm_directory)
    
    # Show VM info
    echo -e "${YELLOW}VM to be deleted:${RESET}"
    echo "  Location: $VM_DIR"
    if [ -f "$VM_DIR/ubuntu-base.img" ]; then
        local vm_size=$(du -sh "$VM_DIR" 2>/dev/null | awk '{print $1}')
        echo "  Size:     $vm_size"
    fi
    echo ""
    
    # Check if VM is running
    if pgrep -f "qemu-system-x86_64.*$VM_NAME" &>/dev/null; then
        print_warn "VM is currently RUNNING!"
        echo ""
        read -p "Stop VM before deleting? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            stop_vm
            sleep 2
        else
            print_error "Cannot delete running VM. Please stop it first."
            exit 1
        fi
    fi
    
    # Confirmation
    echo -e "${RED}This will permanently delete:${RESET}"
    echo "  - All VM files and data"
    echo "  - Ubuntu system image"
    echo "  - All installed packages"
    echo "  - All user files and configurations"
    echo "  - Monitor logs"
    echo ""
    echo -e "${RED}⚠️  NO BACKUP WILL BE CREATED!${RESET}"
    echo -e "${YELLOW}This action CANNOT be undone!${RESET}"
    echo ""
    
    read -p "Are you ABSOLUTELY sure? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Deleting VM without backup..."
        
        # Delete VM directory
        if rm -rf "$VM_DIR"; then
            echo ""
            echo -e "${GREEN}╔════════════════════════════════════════════════════╗${RESET}"
            echo -e "${GREEN}║              VM DELETED SUCCESSFULLY               ║${RESET}"
            echo -e "${GREEN}╚════════════════════════════════════════════════════╝${RESET}"
            echo ""
            print_info "VM deleted: $VM_DIR"
        else
            print_error "Failed to delete VM directory"
            exit 1
        fi
    else
        print_info "Deletion cancelled"
        exit 0
    fi
}

reinstall_vm() {
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}║              REINSTALL VM (FRESH)                  ║${RESET}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    # Check if VM exists
    local found_vm_dir=""
    if [ -d "$HOME/VMs/$VM_NAME" ]; then
        found_vm_dir="$HOME/VMs/$VM_NAME"
    else
        for mount in $(df -h | grep -E '^/dev/' | awk '{print $6}'); do
            if [ -d "$mount/VMs/$VM_NAME" ]; then
                found_vm_dir="$mount/VMs/$VM_NAME"
                break
            fi
        done
    fi
    
    if [ -n "$found_vm_dir" ]; then
        VM_DIR="$found_vm_dir"
        
        echo -e "${YELLOW}Existing VM found:${RESET}"
        echo "  Location: $VM_DIR"
        if [ -f "$VM_DIR/ubuntu-base.img" ]; then
            local vm_size=$(du -sh "$VM_DIR" 2>/dev/null | awk '{print $1}')
            echo "  Size:     $vm_size"
        fi
        echo ""
        
        # Check if VM is running
        if pgrep -f "qemu-system-x86_64.*$VM_NAME" &>/dev/null; then
            print_warn "VM is currently RUNNING!"
            echo ""
            read -p "Stop VM before reinstalling? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                stop_vm
                sleep 2
            else
                print_error "Cannot reinstall while VM is running."
                exit 1
            fi
        fi
        
        echo -e "${RED}This will DELETE all existing VM data and install fresh:${RESET}"
        echo "  - All user files will be lost"
        echo "  - All installed packages will be lost"
        echo "  - All configurations will be lost"
        echo ""
        echo -e "${GREEN}A new clean VM will be installed${RESET}"
        echo ""
        
        read -p "Continue with reinstall? (y/N): " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Reinstall cancelled"
            exit 0
        fi
        
        echo ""
        print_info "Deleting old VM..."
        rm -rf "$VM_DIR"
    else
        print_info "No existing VM found. Installing fresh..."
    fi
    
    echo ""
    print_info "Installing fresh VM..."
    echo ""
    
    # Continue with normal setup
    show_host_specs
    select_disk_location
    setup_vm
    start_vm
}

check_vm_responsive() {
    # Check if QEMU process exists
    if ! pgrep -f "qemu-system-x86_64.*$VM_NAME" >/dev/null; then
        return 1
    fi
    
    # Check if QEMU process is responding (not in D state)
    local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$VM_NAME" | head -1)
    if [ -z "$qemu_pid" ]; then
        return 1
    fi
    
    # Check host disk space - critical check (more aggressive threshold)
    if [ -n "$VM_DIR" ] && [ -d "$VM_DIR" ]; then
        # Use bytes for more accurate check
        local disk_avail=$(df -B1 "$VM_DIR" 2>/dev/null | awk 'NR==2{print $4}' || echo "1000000000")
        local critical_threshold=$((100 * 1024 * 1024))  # 100MB threshold
        
        if [ "$disk_avail" -le "$critical_threshold" ]; then
            local avail_mb=$((disk_avail / 1024 / 1024))
            echo "[$(date)] CRITICAL: Host disk critically low (${avail_mb}MB)! Auto-killing QEMU..." >> "$MONITOR_LOG" 2>/dev/null || true
            print_error "Host disk is CRITICALLY LOW (${avail_mb}MB)! Auto-killing QEMU to prevent system crash..."
            
            # Try graceful shutdown first
            pkill -TERM -f "qemu-system-x86_64.*$VM_NAME" 2>/dev/null
            sleep 2
            
            # Force kill if still running
            if pgrep -f "qemu-system-x86_64.*$VM_NAME" >/dev/null; then
                pkill -9 -f "qemu-system-x86_64.*$VM_NAME" 2>/dev/null
            fi
            
            return 2  # Special return code for disk full
        fi
    fi
    
    # Check process state (D = uninterruptible sleep = frozen)
    local state=$(ps -o state= -p "$qemu_pid" 2>/dev/null | tr -d ' ')
    if [ "$state" = "D" ] || [ "$state" = "Z" ]; then
        return 1
    fi
    
    # Check CPU usage - if 0% for too long, might be frozen
    local cpu_usage=$(ps -o %cpu= -p "$qemu_pid" 2>/dev/null | tr -d ' ')
    if [ -z "$cpu_usage" ]; then
        return 1
    fi
    
    return 0
}

attempt_recovery() {
    local attempt=$1
    print_warn "Attempting recovery #$attempt..."
    
    local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$VM_NAME" | head -1)
    if [ -z "$qemu_pid" ]; then
        print_error "QEMU process not found"
        return 1
    fi
    
    case $attempt in
        1)
            # Try SIGCONT in case it's stopped
            print_info "Sending SIGCONT to QEMU process..."
            kill -CONT "$qemu_pid" 2>/dev/null
            sleep 5
            ;;
        2)
            # Try to flush I/O
            print_info "Attempting to flush I/O..."
            sync
            echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
            sleep 5
            ;;
        3)
            # Try SIGUSR1 (QEMU debug signal)
            print_info "Sending debug signal to QEMU..."
            kill -USR1 "$qemu_pid" 2>/dev/null
            sleep 5
            ;;
        *)
            return 1
            ;;
    esac
    
    # Check if recovery worked
    sleep 2
    if check_vm_responsive; then
        print_info "Recovery successful!"
        return 0
    else
        return 1
    fi
}

ask_reset_vm() {
    echo ""
    print_error "VM appears to be frozen and recovery attempts failed."
    echo -e "${RED}WARNING: Resetting will delete ALL data in the VM!${RESET}"
    echo -e "${YELLOW}This includes:${RESET}"
    echo "  - All files in /home/$USERNAME"
    echo "  - All installed packages"
    echo "  - All configurations"
    echo "  - Persistent disk data"
    echo ""
    echo -e "${CYAN}Options:${RESET}"
    echo "  1) Force kill QEMU and restart (may recover some data)"
    echo "  2) Full reset - delete all VM data and start fresh"
    echo "  3) Do nothing - exit and investigate manually"
    echo ""
    read -p "Choose option [1/2/3]: " choice
    
    case $choice in
        1)
            print_info "Force killing QEMU..."
            pkill -9 -f "qemu-system-x86_64.*$VM_NAME"
            sleep 2
            print_info "Attempting to restart VM..."
            return 0
            ;;
        2)
            print_warn "Performing full reset..."
            pkill -9 -f "qemu-system-x86_64.*$VM_NAME" 2>/dev/null || true
            sleep 2
            
            if [ -d "$VM_DIR" ]; then
                print_info "Backing up old VM to $VM_DIR.backup.$(date +%s)"
                mv "$VM_DIR" "$VM_DIR.backup.$(date +%s)"
            fi
            
            print_info "Setting up fresh VM..."
            setup_vm
            return 0
            ;;
        3)
            print_info "Exiting. VM process may still be running."
            print_info "Manual investigation needed. Check: ps aux | grep qemu"
            exit 0
            ;;
        *)
            print_error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

monitor_vm_health() {
    local freeze_count=0
    local recovery_attempt=0
    
    print_info "Starting VM health monitor..."
    # Ensure MONITOR_LOG is set
    if [ -z "$MONITOR_LOG" ]; then
        MONITOR_LOG="$VM_DIR/monitor.log"
    fi
    echo "Monitor started at $(date)" > "$MONITOR_LOG"
    
    while true; do
        sleep "$FREEZE_CHECK_INTERVAL"
        
        check_vm_responsive
        local responsive_status=$?
        
        # Check if disk is full (return code 2)
        if [ $responsive_status -eq 2 ]; then
            echo "[$(date)] QEMU killed due to disk full" >> "$MONITOR_LOG"
            print_error "VM terminated due to host disk full!"
            echo ""
            echo -e "${RED}╔════════════════════════════════════════════════════╗${RESET}"
            echo -e "${RED}║         VM TERMINATED - DISK FULL                  ║${RESET}"
            echo -e "${RED}╚════════════════════════════════════════════════════╝${RESET}"
            echo ""
            echo -e "${YELLOW}What happened:${RESET}"
            echo "  - Host disk ran out of space (0MB available)"
            echo "  - QEMU was automatically killed to prevent system crash"
            echo "  - VM data may be corrupted"
            echo ""
            echo -e "${CYAN}Next steps:${RESET}"
            echo "  1. Free up disk space immediately"
            echo "  2. Check VM integrity: $VM_DIR"
            echo "  3. Consider moving VM to a larger disk"
            echo ""
            exit 1
        fi
        
        if [ $responsive_status -ne 0 ]; then
            freeze_count=$((freeze_count + 1))
            echo "[$(date)] Freeze check failed ($freeze_count/$FREEZE_THRESHOLD)" >> "$MONITOR_LOG"
            
            if [ $freeze_count -ge $FREEZE_THRESHOLD ]; then
                print_error "VM freeze detected!"
                echo "[$(date)] FREEZE DETECTED" >> "$MONITOR_LOG"
                
                # Try recovery
                recovery_attempt=$((recovery_attempt + 1))
                
                if [ $recovery_attempt -le $RECOVERY_ATTEMPTS ]; then
                    if attempt_recovery $recovery_attempt; then
                        freeze_count=0
                        recovery_attempt=0
                        echo "[$(date)] Recovery successful" >> "$MONITOR_LOG"
                        continue
                    fi
                else
                    # All recovery attempts failed
                    echo "[$(date)] All recovery attempts failed" >> "$MONITOR_LOG"
                    ask_reset_vm
                    
                    # If we get here, user chose option 1 or 2
                    # Reset counters and continue monitoring
                    freeze_count=0
                    recovery_attempt=0
                fi
            fi
        else
            # VM is responsive
            if [ $freeze_count -gt 0 ]; then
                echo "[$(date)] VM recovered naturally" >> "$MONITOR_LOG"
            fi
            freeze_count=0
        fi
    done
}

start_vm_with_monitor() {
    # Start VM in background
    print_info "Starting VM with freeze monitoring..."
    
    # Create a temporary script to run the VM
    local vm_script="$VM_DIR/start_vm_temp.sh"
    cat > "$vm_script" << 'EOF'
#!/bin/bash
# Temporary VM start script
cd "$VM_DIR"

# TCG-specific optimizations
local EXTRA_FLAGS=""
if [ "$USE_KVM" = false ]; then
    print_info "Using TCG optimizations for better performance..."
    # Simpler network for TCG (no multi-queue)
    EXTRA_FLAGS="-device virtio-net-pci,netdev=n0"
else
    # Full features for KVM
    EXTRA_FLAGS="-device virtio-net-pci,netdev=n0,mq=on,vectors=4"
fi

# CRITICAL FIX: cache=unsafe causes data corruption and freezes
# Use cache=writeback with proper AIO for stability
local CACHE_MODE="writeback"
local AIO_MODE="native"  # native is faster and more stable than threads

# For TCG, use threads AIO (native requires KVM)
if [ "$USE_KVM" = false ]; then
    AIO_MODE="threads"
fi

# Create log file for debugging
local LOG_FILE="$VM_DIR/qemu.log"

exec qemu-system-x86_64 \
    $KVM_FLAG \
    -machine q35,accel=$([ "$USE_KVM" = true ] && echo "kvm" || echo "tcg"),kernel_irqchip=on \
    -m "$RAM" \
    -smp "$CPU_CORES",cores="$CPU_CORES",threads=1,sockets=1,maxcpus="$CPU_CORES" \
    -object iothread,id=io1 \
    -drive file="$IMG_FILE",format=qcow2,if=none,id=drive0,cache="$CACHE_MODE",aio="$AIO_MODE",discard=unmap \
    -device virtio-blk-pci,drive=drive0,iothread=io1,num-queues="$CPU_CORES" \
    -drive file="$SEED_FILE",format=raw,if=virtio,cache=none,readonly=on \
    -boot order=c,menu=off,strict=on \
    $EXTRA_FLAGS \
    -netdev user,id=n0,hostfwd=tcp::"$SSH_PORT"-:22,net=10.0.2.0/24,dhcpstart=10.0.2.15 \
    -device virtio-balloon-pci,id=balloon0,deflate-on-oom=on,free-page-reporting=on \
    -device virtio-rng-pci,rng=rng0 \
    -object rng-random,id=rng0,filename=/dev/urandom \
    -nographic \
    -serial mon:stdio \
    -no-reboot \
    -rtc base=localtime,clock=host,driftfix=slew \
    -global kvm-pit.lost_tick_policy=discard \
    -overcommit mem-lock=off \
    -overcommit cpu-pm=on \
    -msg timestamp=on \
    -D "$LOG_FILE" \
    -pidfile "$VM_DIR/qemu.pid" \
    -name "$VM_NAME",process="$VM_NAME",debug-threads=on
EOF
    
    chmod +x "$vm_script"
    
    # Start VM script in background
    bash "$vm_script" &
    local vm_pid=$!
    
    # Wait for VM to start
    sleep 5
    
    # Start monitor in background
    monitor_vm_health &
    local monitor_pid=$!
    echo $monitor_pid > "$VM_DIR/monitor.pid"
    
    print_info "VM started with health monitor (PID: $monitor_pid)"
    print_info "Monitor log: $MONITOR_LOG"
    
    # Wait for VM process
    wait $vm_pid
    
    # Stop monitor when VM exits
    if kill -0 $monitor_pid 2>/dev/null; then
        kill $monitor_pid 2>/dev/null
    fi
    rm -f "$VM_DIR/monitor.pid" "$vm_script"
}

show_help() {
    cat << EOF
${CYAN}Ubuntu 22.04 VM Manager${RESET}
Modified from: quanvm0501 (BlackCatOfficial), BiraloGaming

Usage: $0 [OPTION]

Options:
  (no option)   Setup and start VM in terminal (auto-login)
  -s, --start   Start VM with GUI
  -m, --monitor Start VM with freeze monitoring
  -k, --stop    Stop VM
  -r, --remove  Remove/Delete VM (with backup, y/N confirm)
  -rm           Remove VM WITHOUT backup (y/N confirm)
  -n, --new     Reinstall VM (delete old + install fresh)
  -i, --info    Show VM information
  --help        Show this help

Examples:
  $0              # Setup and start VM (terminal, auto-login)
  $0 -s           # Start VM with GUI
  $0 -m           # Start VM with freeze monitoring
  $0 -k           # Stop VM
  $0 -r           # Remove VM with backup
  $0 -rm          # Remove VM without backup (faster)
  $0 -n           # Reinstall fresh VM
  $0 -i           # Show info

Credentials:
  Username: $USERNAME
  Password: $PASSWORD
  SSH:      ssh -p $SSH_PORT $USERNAME@localhost

Terminal Controls:
  Exit:     Ctrl+A, then X
  Monitor:  Ctrl+A, then C

Features:
  ✓ Choose disk location for VM installation
  ✓ Host system specs check before start
  ✓ Low storage warning (< 500MB)
  ✓ Auto-kill QEMU when host disk full (0MB)
  ✓ Auto-login to terminal after boot
  ✓ Cloud-init auto-configuration
  ✓ SSH ready on port $SSH_PORT
  ✓ KVM acceleration (if available)
  ✓ Automatic freeze detection & recovery
  ✓ No manual installation needed

Disk Selection:
  - Press ENTER: Auto-select disk with most space
  - Enter number: Choose specific disk
  - Enter 0: Exit setup

Files:
  VM Dir:   Selected during setup
  Image:    20GB (grows as needed)
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
        show_host_specs
        select_disk_location
        start_vm_gui
        ;;
    -m|--monitor)
        show_host_specs
        select_disk_location
        setup_vm
        start_vm_with_monitor
        ;;
    -k|--stop)
        # Find existing VM
        VM_DIR=$(find_vm_directory false)
        if [ -n "$VM_DIR" ]; then
            setup_vm_paths
            stop_vm
        else
            print_warn "VM not found, nothing to stop"
        fi
        ;;
    -r|--remove)
        remove_vm
        ;;
    -rm)
        remove_vm_no_backup
        ;;
    -n|--new)
        reinstall_vm
        ;;
    -i|--info)
        # Find existing VM
        VM_DIR=$(find_vm_directory false)
        if [ -n "$VM_DIR" ]; then
            setup_vm_paths
            vm_info
        else
            print_error "VM not found!"
            echo "Run '$0' to create a new VM"
            exit 1
        fi
        ;;
    --help)
        show_help
        ;;
    "")
        show_host_specs
        select_disk_location
        setup_vm
        start_vm
        ;;
    *)
        print_error "Invalid option: $1"
        echo "Run '$0 --help' for usage"
        exit 1
        ;;
esac
