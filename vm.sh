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

# I/O and stability settings
IO_THREADS="4"  # Number of I/O threads for disk operations

# Freeze detection settings
FREEZE_CHECK_INTERVAL="10"  # Seconds between freeze checks
FREEZE_THRESHOLD="3"  # Number of failed checks before declaring freeze
RECOVERY_ATTEMPTS="3"  # Number of recovery attempts before asking to reset
MONITOR_LOG="$VM_DIR/monitor.log"

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
        -object iothread,id=io2 \
        -drive file="$IMG_FILE",format=qcow2,if=none,id=drive0,cache="$CACHE_MODE",aio="$AIO_MODE",discard=unmap \
        -device virtio-blk-pci,drive=drive0,iothread=io1,num-queues="$CPU_CORES" \
        -drive file="$PERSISTENT_DISK",format=qcow2,if=none,id=drive1,cache="$CACHE_MODE",aio="$AIO_MODE",discard=unmap \
        -device virtio-blk-pci,drive=drive1,iothread=io2,num-queues="$CPU_CORES" \
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
        -object iothread,id=io2 \
        -drive file="$IMG_FILE",format=qcow2,if=none,id=drive0,cache="$CACHE_MODE",aio="$AIO_MODE",discard=unmap \
        -device virtio-blk-pci,drive=drive0,iothread=io1,num-queues="$CPU_CORES" \
        -drive file="$PERSISTENT_DISK",format=qcow2,if=none,id=drive1,cache="$CACHE_MODE",aio="$AIO_MODE",discard=unmap \
        -device virtio-blk-pci,drive=drive1,iothread=io2,num-queues="$CPU_CORES" \
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
    echo "Monitor started at $(date)" > "$MONITOR_LOG"
    
    while true; do
        sleep "$FREEZE_CHECK_INTERVAL"
        
        if ! check_vm_responsive; then
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
    
    # Start VM
    start_vm &
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
    rm -f "$VM_DIR/monitor.pid"
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
  -i, --info    Show VM information
  --help        Show this help

Examples:
  $0              # Setup and start VM (terminal, auto-login)
  $0 -s           # Start VM with GUI
  $0 -m           # Start VM with freeze monitoring
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
  ✓ Automatic freeze detection & recovery
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
    -m|--monitor)
        setup_vm
        start_vm_with_monitor
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
