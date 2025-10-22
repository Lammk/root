
#!/usr/bin/env bash
# Strict mode for better error handling
set -euo pipefail
IFS=$'\n\t'

# =============================
# PROOT FAKE ROOT ENVIRONMENT
# Tạo môi trường root giả lập với proot
# Có thể sử dụng apt và các công cụ system
# =============================

# Cấu hình
ROOTFS_DIR="${FAKEROOT_DIR:-$HOME/.fakeroot-proot}"
PROOT_BIN="${PROOT_BIN:-$HOME/.local/bin/proot}"
MAX_RETRIES="${MAX_RETRIES:-3}"
TIMEOUT="${TIMEOUT:-30}"
ARCH="$(uname -m)"
ALPINE_ARCH=""
ARCH_ALT=""  # Initialize to avoid unbound variable

# Script version
SCRIPT_VERSION="2.0.0"
SCRIPT_DATE="22/10/2025"

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_WHITE='\033[0;37m'
COLOR_RESET='\033[0m'

# =============================
# FUNCTIONS
# =============================
print_info() {
    echo -e "${COLOR_GREEN}[THÔNG TIN]${COLOR_RESET} $1" >&2
}

print_warn() {
    echo -e "${COLOR_YELLOW}[CẢNH BÁO]${COLOR_RESET} $1" >&2
}

print_error() {
    echo -e "${COLOR_RED}[LỖI]${COLOR_RESET} $1" >&2
}

# Cleanup khi exit
cleanup() {
    local exit_code=$?
    # Xóa tất cả temp files
    if [ -n "${ROOTFS_FILE:-}" ]; then
        rm -f "$ROOTFS_FILE" "${ROOTFS_FILE%.xz}" "${ROOTFS_FILE%.gz}" "${ROOTFS_FILE%.bz2}" 2>/dev/null || true
    fi
    # Xóa các temp files khác
    rm -f /tmp/rootfs_$$.* 2>/dev/null || true
    return $exit_code
}
trap cleanup EXIT INT TERM HUP

# Download file với retry (hỗ trợ cả wget và curl)
download_file() {
    local url="$1"
    local output="$2"
    local retries="${3:-$MAX_RETRIES}"
    
    # Xác định tool download
    local download_cmd=""
    if command -v wget &>/dev/null; then
        download_cmd="wget"
    elif command -v curl &>/dev/null; then
        download_cmd="curl"
    else
        print_error "Không tìm thấy wget hoặc curl"
        return 1
    fi
    
    for ((i=1; i<=retries; i++)); do
        if [ "$download_cmd" = "wget" ]; then
            # wget: bỏ -q để show progress hoạt động
            if wget --tries=1 --timeout="$TIMEOUT" --no-hsts --show-progress -O "$output" "$url" 2>&1 | grep -v '^--'; then
                if [ -s "$output" ]; then
                    # Verify file is not HTML error page
                    if file "$output" | grep -qE 'gzip|XZ|tar|compressed'; then
                        return 0
                    elif [ "${output##*.}" = "gz" ] || [ "${output##*.}" = "xz" ]; then
                        return 0  # Trust extension if file command fails
                    fi
                fi
            fi
        else
            # curl fallback
            if curl -fSL --connect-timeout "$TIMEOUT" --max-time $((TIMEOUT*2)) -o "$output" "$url" 2>&1; then
                [ -s "$output" ] && return 0
            fi
        fi
        
        [ $i -lt $retries ] && print_warn "Thử lại ($i/$retries)..."
        rm -f "$output"  # Xóa file lỗi trước khi retry
        sleep $((i * 2))  # Exponential backoff
    done
    return 1
}

# Giải nén file tar
extract_tar() {
    local file="$1"
    local dest="$2"
    
    [ ! -f "$file" ] && { print_error "File không tồn tại: $file"; return 1; }
    [ ! -d "$dest" ] && { print_error "Thư mục đích không tồn tại: $dest"; return 1; }
    
    print_info "Đang giải nén $(basename "$file")..."
    
    # Kiểm tra file size
    local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
    if [ "$file_size" -lt 1000 ]; then
        print_error "File quá nhỏ ($file_size bytes), có thể bị lỗi"
        return 1
    fi
    
    # Tự động phát hiện và giải nén
    if tar -xf "$file" -C "$dest" 2>&1 | head -n 5; then
        print_info "Giải nén thành công!"
        return 0
    fi
    
    # Fallback: thử giải nén thủ công
    print_warn "Tar tự động thất bại, thử phương pháp thủ công..."
    case "$file" in
        *.tar.xz)
            xz -d "$file" && tar -xf "${file%.xz}" -C "$dest"
            ;;
        *.tar.gz)
            gzip -d "$file" && tar -xf "${file%.gz}" -C "$dest"
            ;;
        *.tar.bz2)
            bzip2 -d "$file" && tar -xf "${file%.bz2}" -C "$dest"
            ;;
        *)
            print_error "Định dạng file không được hỗ trợ: $file"
            return 1
            ;;
    esac
}

print_banner() {
    clear
    echo -e "${COLOR_CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════╗
║                                                      ║
║           PROOT FAKE ROOT ENVIRONMENT                ║
║                                                      ║
║        Môi trường root giả lập với proot            ║
║        Có thể sử dụng apt, dpkg và các tool         ║
║                                                      ║
╚══════════════════════════════════════════════════════╝
EOF
    echo -e "${COLOR_RESET}"
}

display_complete() {
    echo -e "${COLOR_WHITE}___________________________________________________${COLOR_RESET}"
    echo -e ""
    echo -e "           ${COLOR_CYAN}-----> Cài đặt hoàn tất! <----${COLOR_RESET}"
    echo -e "${COLOR_WHITE}___________________________________________________${COLOR_RESET}"
    echo ""
}

# =============================
# KIỂM TRA KIẾN TRÚC
# =============================
check_architecture() {
    # Chỉ chạy một lần
    [ -n "${ARCH_ALT:-}" ] && [ "$ARCH_ALT" != "" ] && return 0
    
    case "$ARCH" in
        x86_64)
            ARCH_ALT="amd64"
            ALPINE_ARCH="x86_64"
            ;;
        aarch64|arm64)
            ARCH_ALT="arm64"
            ALPINE_ARCH="aarch64"
            ;;
        armv7l|armhf)
            ARCH_ALT="armhf"
            ALPINE_ARCH="armv7"
            ;;
        i386|i686)
            ARCH_ALT="i386"
            ALPINE_ARCH="x86"
            ;;
        *)
            print_error "Kiến trúc CPU không được hỗ trợ: $ARCH"
            exit 1
            ;;
    esac
    print_info "Phát hiện kiến trúc: $ARCH ($ARCH_ALT)"
}

# =============================
# TẢI PROOT
# =============================
download_proot() {
    # Kiểm tra đã có proot chưa
    if [ -x "$PROOT_BIN" ]; then
        print_info "Proot đã tồn tại, bỏ qua tải xuống"
        return 0
    fi
    
    print_info "Đang tải proot cho $ARCH..."
    mkdir -p "$(dirname "$PROOT_BIN")"
    
    local PROOT_URLS=(
        "https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-${ARCH}-static"
        "https://raw.githubusercontent.com/foxytouxxx/freeroot/main/proot-${ARCH}"
        "https://github.com/termux/proot/releases/latest/download/proot-${ARCH}"
    )
    
    for url in "${PROOT_URLS[@]}"; do
        print_info "Đang thử: $(basename "$url")"
        if download_file "$url" "$PROOT_BIN"; then
            chmod +x "$PROOT_BIN"
            print_info "Tải proot thành công!"
            return 0
        fi
        rm -f "$PROOT_BIN"
    done
    
    print_error "Không thể tải proot từ bất kỳ nguồn nào"
    return 1
}

# =============================
# CHỌN DISTRO
# =============================
choose_distro() {
    # Đảm bảo architecture đã được check
    [ -z "${ARCH_ALT:-}" ] && {
        print_error "ARCH_ALT chưa được khởi tạo. Gọi check_architecture() trước."
        return 1
    }
    
    echo ""
    echo -e "${COLOR_BLUE}Chọn distro Linux muốn cài đặt:${COLOR_RESET}"
    echo ""
    echo "1) Ubuntu 24.04 LTS (Noble)"
    echo "2) Ubuntu 22.04 LTS (Jammy) ${COLOR_GREEN}⭐ KHÚYEN NGHỊ${COLOR_RESET}"
    echo "3) Ubuntu 20.04 LTS (Focal)"
    echo "4) Alpine Linux (nhẹ nhất)"
    echo "5) Arch Linux (chỉ amd64)"
    echo ""
    read -p "Nhập lựa chọn (1-5) [mặc định: 2]: " distro_choice
    distro_choice=${distro_choice:-2}
    
    # Validate input
    if ! [[ "$distro_choice" =~ ^[1-5]$ ]]; then
        print_error "Lựa chọn không hợp lệ: $distro_choice"
        return 1
    fi
    
    case $distro_choice in
        1)
            DISTRO_NAME="Ubuntu 24.04"
            ROOTFS_URL="http://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-${ARCH_ALT}.tar.gz"
            ;;
        2)
            DISTRO_NAME="Ubuntu 22.04"
            ROOTFS_URL="http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-${ARCH_ALT}.tar.gz"
            ;;
        3)
            DISTRO_NAME="Ubuntu 20.04"
            ROOTFS_URL="http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.4-base-${ARCH_ALT}.tar.gz"
            ;;
        4)
            DISTRO_NAME="Alpine Linux"
            # Validate ALPINE_ARCH
            [ -z "$ALPINE_ARCH" ] && {
                print_error "ALPINE_ARCH chưa được khởi tạo"
                return 1
            }
            # Cập nhật lên phiên bản Alpine mới nhất
            ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/${ALPINE_ARCH}/alpine-minirootfs-3.20.3-${ALPINE_ARCH}.tar.gz"
            ;;
        5)
            DISTRO_NAME="Arch Linux"
            # Sử dụng Arch Linux Bootstrap
            case "$ARCH_ALT" in
                amd64) ROOTFS_URL="https://geo.mirror.pkgbuild.com/iso/latest/archlinux-bootstrap-x86_64.tar.gz" ;;
                *) print_error "Kiến trúc không được hỗ trợ cho Arch Linux: $ARCH_ALT (chỉ hỗ trợ amd64)"; return 1 ;;
            esac
            ;;
        *)
            print_error "Lựa chọn không hợp lệ"
            exit 1
            ;;
    esac
}

# =============================
# TẢI VÀ CÀI ĐẶT ROOTFS
# =============================
install_rootfs() {
    if [ -f "$ROOTFS_DIR/.installed" ]; then
        print_info "Rootfs đã được cài đặt"
        return 0
    fi
    
    print_info "Đang cài đặt $DISTRO_NAME..."
    
    mkdir -p "$ROOTFS_DIR"
    
    # Tải rootfs
    print_info "Đang tải rootfs: $(basename "$ROOTFS_URL")"
    
    # Xác định extension từ URL (cải thiện logic)
    if [[ "$ROOTFS_URL" == *.tar.xz ]]; then
        ROOTFS_FILE="/tmp/rootfs_$$.tar.xz"
    elif [[ "$ROOTFS_URL" == *.tar.gz ]]; then
        ROOTFS_FILE="/tmp/rootfs_$$.tar.gz"
    elif [[ "$ROOTFS_URL" == *.tar.bz2 ]]; then
        ROOTFS_FILE="/tmp/rootfs_$$.tar.bz2"
    elif [[ "$ROOTFS_URL" == *.tar ]]; then
        ROOTFS_FILE="/tmp/rootfs_$$.tar"
    else
        # Default to tar.gz if unknown
        ROOTFS_FILE="/tmp/rootfs_$$.tar.gz"
    fi
    
    # Export for cleanup
    export ROOTFS_FILE
    
    # Tải với fallback
    if ! download_file "$ROOTFS_URL" "$ROOTFS_FILE"; then
        print_error "Không thể tải rootfs chính"
        
        # URL dự phòng
        case "$DISTRO_NAME" in
            "Alpine Linux")
                print_info "Đang thử Alpine 3.19.1..."
                ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/${ALPINE_ARCH}/alpine-minirootfs-3.19.1-${ALPINE_ARCH}.tar.gz"
                ROOTFS_FILE="/tmp/rootfs_$$.tar.gz"
                download_file "$ROOTFS_URL" "$ROOTFS_FILE" || return 1
                ;;
            *)
                return 1
                ;;
        esac
    fi
    
    # Kiểm tra file
    if [ ! -s "$ROOTFS_FILE" ]; then
        print_error "File rootfs không hợp lệ"
        return 1
    fi
    
    # Giải nén
    extract_tar "$ROOTFS_FILE" "$ROOTFS_DIR" || {
        print_error "Không thể giải nén rootfs"
        return 1
    }
    
    # Cấu hình DNS
    print_info "Đang cấu hình DNS..."
    mkdir -p "$ROOTFS_DIR/etc"
    cat > "$ROOTFS_DIR/etc/resolv.conf" << EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
    
    # Tạo thư mục cần thiết
    mkdir -p "$ROOTFS_DIR"/{dev,sys,proc,tmp,root,home,var/log,etc/ssl/certs}
    
    # Fix GPG keys và SSL cho Ubuntu/Debian
    if [[ "$DISTRO_NAME" == Ubuntu* ]] || [[ "$DISTRO_NAME" == Debian* ]]; then
        print_info "Đang cấu hình GPG keys và SSL cho $DISTRO_NAME..."
        fix_ubuntu_gpg_keys
        fix_ssl_certificates
    fi
    
    # Đánh dấu đã cài đặt
    {
        echo "$DISTRO_NAME"
        echo "Installed: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Architecture: $ARCH ($ARCH_ALT)"
    } > "$ROOTFS_DIR/.distro_name"
    touch "$ROOTFS_DIR/.installed"
    
    print_info "Cài đặt $DISTRO_NAME hoàn tất!"
}

# =============================
# FIX GPG KEYS CHO UBUNTU/DEBIAN
# =============================
fix_ubuntu_gpg_keys() {
    # Fix permissions cho apt keyrings
    if [ -d "$ROOTFS_DIR/etc/apt/trusted.gpg.d" ]; then
        chmod 644 "$ROOTFS_DIR/etc/apt/trusted.gpg.d/"*.gpg 2>/dev/null || true
        chmod 755 "$ROOTFS_DIR/etc/apt/trusted.gpg.d" 2>/dev/null || true
    fi
    
    # Tạo thư mục apt cần thiết
    mkdir -p "$ROOTFS_DIR/var/lib/apt/lists/partial"
    mkdir -p "$ROOTFS_DIR/var/cache/apt/archives/partial"
    chmod 755 "$ROOTFS_DIR/var/lib/apt/lists" 2>/dev/null || true
    chmod 700 "$ROOTFS_DIR/var/lib/apt/lists/partial" 2>/dev/null || true
    
    # Tạo file cấu hình apt để bỏ qua GPG check và fix dpkg issues
    mkdir -p "$ROOTFS_DIR/etc/apt/apt.conf.d"
    cat > "$ROOTFS_DIR/etc/apt/apt.conf.d/99-proot-no-check" << 'EOF'
// Cấu hình cho proot environment
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
APT::Get::AllowUnauthenticated "true";
APT::Get::Assume-Yes "false";
Acquire::Check-Valid-Until "false";

// Fix dpkg errors trong proot
DPkg::Options {
   "--force-confold";
   "--force-confdef";
   "--force-overwrite";
};

// Cho phép cài packages với services
DPkg::Pre-Install-Pkgs {"/bin/true";};
DPkg::Post-Invoke {"/bin/true";};

// Không fail khi services không start được
DPkg::NoTriggers "true";
EOF
    
    # Tạo policy-rc.d để ngăn services tự khởi động (nhưng cho phép cài đặt)
    mkdir -p "$ROOTFS_DIR/usr/sbin"
    cat > "$ROOTFS_DIR/usr/sbin/policy-rc.d" << 'POLICY_EOF'
#!/bin/bash
# Cho phép cài đặt packages nhưng không khởi động services trong proot
# Exit code 101 = action forbidden by policy
echo "[PROOT] Service action blocked: $@" >&2
exit 101
POLICY_EOF
    chmod +x "$ROOTFS_DIR/usr/sbin/policy-rc.d"
    
    # Tạo fake systemctl để tránh lỗi (enhanced version with better compatibility)
    mkdir -p "$ROOTFS_DIR/usr/local/bin"
    cat > "$ROOTFS_DIR/usr/local/bin/systemctl" << 'SYSTEMCTL_EOF'
#!/bin/bash
# Enhanced fake systemctl for proot - maximum compatibility

# Parse arguments
CMD="$1"
SERVICE="$2"

case "$CMD" in
    start|stop|restart|reload|try-restart|reload-or-restart|try-reload-or-restart)
        # Simulate successful service action
        [ -n "$SERVICE" ] && echo "[PROOT] systemctl $CMD $SERVICE - simulated success" >&2
        exit 0
        ;;
    enable|disable|mask|unmask|preset|preset-all|reenable)
        # Simulate successful configuration
        if [ -n "$SERVICE" ]; then
            echo "[PROOT] systemctl $CMD $SERVICE - configuration simulated" >&2
            # Create fake symlink tracking
            mkdir -p /var/lib/proot-systemctl 2>/dev/null || true
            touch "/var/lib/proot-systemctl/$SERVICE.$CMD" 2>/dev/null || true
        fi
        exit 0
        ;;
    status)
        # Realistic status output
        if [ -n "$SERVICE" ]; then
            echo "● $SERVICE"
            echo "   Loaded: loaded (/lib/systemd/system/$SERVICE; disabled; vendor preset: enabled)"
            echo "   Active: inactive (dead)"
            echo "     Docs: man:$SERVICE(8)"
            echo ""
            echo "[PROOT] Services cannot run in proot environment"
        fi
        exit 3
        ;;
    is-active)
        echo "inactive"
        exit 3
        ;;
    is-enabled)
        # Check if we "enabled" it before
        if [ -f "/var/lib/proot-systemctl/$SERVICE.enable" ] 2>/dev/null; then
            echo "enabled"
            exit 0
        fi
        echo "disabled"
        exit 1
        ;;
    is-failed)
        echo "inactive"
        exit 1
        ;;
    daemon-reload|daemon-reexec)
        echo "[PROOT] systemctl $CMD - acknowledged" >&2
        exit 0
        ;;
    reset-failed)
        [ -n "$SERVICE" ] && echo "[PROOT] systemctl reset-failed $SERVICE - cleared" >&2
        exit 0
        ;;
    list-units|list-unit-files|list-sockets|list-timers)
        echo "UNIT FILE                              STATE"
        echo "[PROOT] No real units in proot environment"
        # Show fake units if any were "enabled"
        if [ -d /var/lib/proot-systemctl ] 2>/dev/null; then
            for f in /var/lib/proot-systemctl/*.enable 2>/dev/null; do
                [ -f "$f" ] && basename "$f" .enable | awk '{print $1 " enabled"}'
            done
        fi
        exit 0
        ;;
    show|cat)
        [ -n "$SERVICE" ] && echo "[PROOT] systemctl $CMD $SERVICE - no data available" >&2
        exit 0
        ;;
    --version|-v)
        echo "systemctl 249 (fake for proot)"
        echo "Does not actually manage services"
        echo "All operations are simulated"
        exit 0
        ;;
    --help|-h)
        cat << 'HELP'
systemctl [OPTIONS...] COMMAND ...

Fake systemctl for proot environment.
All commands are accepted but services don't actually run.

Commands:
  start/stop/restart SERVICE   Simulate service control
  enable/disable SERVICE       Simulate service configuration
  status SERVICE               Show simulated status
  is-active SERVICE            Check if active (always inactive)
  is-enabled SERVICE           Check if enabled
  daemon-reload                Acknowledge reload
  list-units                   List simulated units

Note: This is a fake implementation for package installation compatibility.
HELP
        exit 0
        ;;
    *)
        # Accept any other command silently
        [ -n "$CMD" ] && echo "[PROOT] systemctl $CMD $@ - accepted" >&2
        exit 0
        ;;
esac
SYSTEMCTL_EOF
    chmod +x "$ROOTFS_DIR/usr/local/bin/systemctl"
    
    # Tạo fake service command (enhanced)
    cat > "$ROOTFS_DIR/usr/local/bin/service" << 'SERVICE_EOF'
#!/bin/bash
# Enhanced fake service command for proot

if [ $# -eq 0 ]; then
    echo "Usage: service < option > | --status-all | [ service_name [ command | --full-restart ] ]"
    exit 1
fi

if [ "$1" = "--status-all" ]; then
    echo "[PROOT] No services running in proot environment"
    exit 0
fi

SERVICE_NAME="$1"
ACTION="${2:-status}"

case "$ACTION" in
    start|stop|restart|reload|force-reload|status)
        echo "[PROOT] service $SERVICE_NAME $ACTION - simulated"
        exit 0
        ;;
    *)
        echo "[PROOT] service $SERVICE_NAME $ACTION - accepted"
        exit 0
        ;;
esac
SERVICE_EOF
    chmod +x "$ROOTFS_DIR/usr/local/bin/service"
    
    # Tạo fake invoke-rc.d (enhanced)
    mkdir -p "$ROOTFS_DIR/usr/local/sbin"
    cat > "$ROOTFS_DIR/usr/local/sbin/invoke-rc.d" << 'INVOKE_EOF'
#!/bin/bash
# Enhanced fake invoke-rc.d for proot
SCRIPT="$1"
ACTION="$2"

# Simulate success for all actions
case "$ACTION" in
    start|stop|restart|reload|force-reload|status)
        echo "[PROOT] invoke-rc.d $SCRIPT $ACTION - simulated"
        exit 0
        ;;
    *)
        echo "[PROOT] invoke-rc.d $@ - accepted"
        exit 0
        ;;
esac
INVOKE_EOF
    chmod +x "$ROOTFS_DIR/usr/local/sbin/invoke-rc.d" 2>/dev/null || true
    
    # Tạo fake update-rc.d
    cat > "$ROOTFS_DIR/usr/local/sbin/update-rc.d" << 'UPDATERC_EOF'
#!/bin/bash
# Fake update-rc.d for proot
echo "[PROOT] update-rc.d $@ - simulated"
exit 0
UPDATERC_EOF
    chmod +x "$ROOTFS_DIR/usr/local/sbin/update-rc.d" 2>/dev/null || true
    
    # Tạo fake dbus-daemon (many services need this)
    cat > "$ROOTFS_DIR/usr/local/bin/dbus-daemon" << 'DBUS_EOF'
#!/bin/bash
# Fake dbus-daemon for proot
if [ "$1" = "--version" ]; then
    echo "D-Bus Message Bus Daemon (fake for proot) 1.12.20"
    exit 0
fi
echo "[PROOT] dbus-daemon $@ - cannot run in proot"
exit 1
DBUS_EOF
    chmod +x "$ROOTFS_DIR/usr/local/bin/dbus-daemon" 2>/dev/null || true
    
    # Tạo fake start-stop-daemon
    cat > "$ROOTFS_DIR/usr/local/sbin/start-stop-daemon" << 'SSD_EOF'
#!/bin/bash
# Fake start-stop-daemon for proot
echo "[PROOT] start-stop-daemon $@ - simulated"
exit 0
SSD_EOF
    chmod +x "$ROOTFS_DIR/usr/local/sbin/start-stop-daemon" 2>/dev/null || true
    
    # Tạo thư mục cho systemd units (để packages không fail)
    mkdir -p "$ROOTFS_DIR/lib/systemd/system"
    mkdir -p "$ROOTFS_DIR/etc/systemd/system"
    mkdir -p "$ROOTFS_DIR/var/lib/proot-systemctl"
    
    # Tạo fake /run/systemd/system để packages detect systemd
    mkdir -p "$ROOTFS_DIR/run/systemd/system"
    touch "$ROOTFS_DIR/run/systemd/system/.proot-fake" 2>/dev/null || true
    
    # Tạo script fix GPG trong rootfs
    cat > "$ROOTFS_DIR/usr/local/bin/fix-apt-keys" << 'FIXKEYS_EOF'
#!/bin/bash
# Script fix GPG keys cho Ubuntu/Debian trong proot

echo "[*] Fixing APT GPG keys..."

# Fix permissions
if [ -d /etc/apt/trusted.gpg.d ]; then
    chmod 644 /etc/apt/trusted.gpg.d/*.gpg 2>/dev/null || true
    chmod 755 /etc/apt/trusted.gpg.d 2>/dev/null || true
fi

# Tạo thư mục cho apt user
mkdir -p /var/lib/apt/lists/partial
chmod 755 /var/lib/apt/lists
chmod 700 /var/lib/apt/lists/partial

# Import Ubuntu keys nếu thiếu
if command -v apt-key &>/dev/null; then
    echo "[*] Importing Ubuntu archive keys..."
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 871920D1991BC93C 2>/dev/null || true
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3B4FE6ACC0B21F32 2>/dev/null || true
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 871920D1991BC93C 2>/dev/null || true
fi

# Disable signature check tạm thời
cat > /etc/apt/apt.conf.d/99-proot-no-check << 'APTCONF'
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
APT::Get::AllowUnauthenticated "true";
APTCONF

echo "[*] Done! You can now run: apt update"
FIXKEYS_EOF
    
    chmod +x "$ROOTFS_DIR/usr/local/bin/fix-apt-keys" 2>/dev/null || true
    
    # Tạo script fix dpkg errors
    cat > "$ROOTFS_DIR/usr/local/bin/fix-dpkg-errors" << 'FIXDPKG_EOF'
#!/bin/bash
# Script fix dpkg errors trong proot

echo "[*] Fixing dpkg errors..."

# Fix dpkg database
echo "[*] Cleaning dpkg database..."
dpkg --configure -a 2>/dev/null || true
apt-get install -f -y 2>/dev/null || true

# Fix broken packages (không xóa, chỉ reconfigure)
echo "[*] Fixing broken packages..."
for pkg in $(dpkg -l | grep "^iU\|^iF" | awk '{print $2}'); do
    echo "  - Reconfiguring $pkg"
    dpkg --configure --force-all $pkg 2>/dev/null || true
done

# Clean apt cache
echo "[*] Cleaning apt cache..."
apt-get clean
rm -rf /var/lib/apt/lists/*
apt-get update -qq 2>/dev/null || true

# Reconfigure packages
echo "[*] Reconfiguring packages..."
dpkg --configure -a 2>/dev/null || true

echo "[*] Done! You can now install packages."
echo "    Recommended: apt install -y --no-install-recommends <package>"
echo "    With services: apt install -y <package> (services won't start but package will install)"
FIXDPKG_EOF
    
    chmod +x "$ROOTFS_DIR/usr/local/bin/fix-dpkg-errors" 2>/dev/null || true
    
    print_info "GPG keys và dpkg đã được cấu hình"
}

# =============================
# FIX SSL CERTIFICATES CHO CURL
# =============================
fix_ssl_certificates() {
    print_info "Đang cấu hình SSL certificates..."
    
    # Tạo script fix curl/wget SSL errors
    cat > "$ROOTFS_DIR/usr/local/bin/fix-ssl-certs" << 'FIXSSL_EOF'
#!/bin/bash
# Fix SSL certificates cho curl/wget trong proot

echo "[*] Fixing SSL certificates..."

# Cài đặt ca-certificates nếu chưa có
if ! dpkg -l | grep -q ca-certificates; then
    echo "[*] Installing ca-certificates..."
    apt-get update -qq 2>/dev/null
    apt-get install -y --no-install-recommends ca-certificates 2>/dev/null || true
fi

# Update certificates
echo "[*] Updating certificates..."
update-ca-certificates --fresh 2>/dev/null || true

# Tạo symlinks nếu thiếu
if [ ! -f /etc/ssl/certs/ca-certificates.crt ]; then
    mkdir -p /etc/ssl/certs
    if [ -f /usr/share/ca-certificates/mozilla/*.crt ]; then
        cat /usr/share/ca-certificates/mozilla/*.crt > /etc/ssl/certs/ca-certificates.crt 2>/dev/null || true
    fi
fi

# Set environment variables
cat >> /root/.bashrc << 'BASHRC'
# SSL certificates
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export SSL_CERT_DIR=/etc/ssl/certs
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
BASHRC

echo "[*] Done! SSL certificates configured."
echo "    Reload shell: source ~/.bashrc"
FIXSSL_EOF
    
    chmod +x "$ROOTFS_DIR/usr/local/bin/fix-ssl-certs" 2>/dev/null || true
    
    # Pre-configure SSL environment
    cat >> "$ROOTFS_DIR/root/.bashrc" << 'BASHRC_SSL'

# SSL certificates for curl/wget
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export SSL_CERT_DIR=/etc/ssl/certs
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
BASHRC_SSL
    
    print_info "SSL certificates đã được cấu hình"
}

# =============================
# TẠO SCRIPT KHỞI ĐộNG
# =============================
create_startup_script() {
    cat > "$ROOTFS_DIR/root/.startup.sh" << 'STARTUP_EOF'
#!/bin/bash
set +e  # Không exit khi có lỗi

GREEN='\033[0;32m' CYAN='\033[0;36m' YELLOW='\033[1;33m' RESET='\033[0m'

clear
printf "${CYAN}╔══════════════════════════════════════════════════════╗\n║           CHÀO MỬNG ĐẾN FAKE ROOT!                 ║\n╚══════════════════════════════════════════════════════╝${RESET}\n\n"

printf "${GREEN}Thông tin hệ thống:${RESET}\n"
printf "  OS: %s\n" "$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo 'Unknown')"
printf "  Kernel: %s | Arch: %s | User: %s (UID: %s)\n\n" "$(uname -r)" "$(uname -m)" "$(whoami)" "$(id -u)"

printf "${YELLOW}Môi trường fake root với proot - Có thể sử dụng apt/apk/pacman${RESET}\n\n"

# Khởi tạo package manager
if command -v apt &>/dev/null && [ ! -f /root/.apt_updated ]; then
    printf "${GREEN}Khởi tạo apt...${RESET}\n"
    
    # Fix GPG keys trước khi update
    if [ -f /usr/local/bin/fix-apt-keys ]; then
        printf "${YELLOW}Đang fix GPG keys...${RESET}\n"
        /usr/local/bin/fix-apt-keys 2>&1 | grep -E "\[\*\]|Done" || true
    fi
    
    # Cài đặt ca-certificates cho curl/wget
    if ! dpkg -l | grep -q ca-certificates; then
        printf "${YELLOW}Đang cài đặt ca-certificates...${RESET}\n"
        apt-get install -y --no-install-recommends ca-certificates 2>/dev/null || true
    fi
    
    # Fix permissions cho apt
    chmod 644 /etc/apt/trusted.gpg.d/*.gpg 2>/dev/null || true
    mkdir -p /var/lib/apt/lists/partial
    chmod 755 /var/lib/apt/lists 2>/dev/null || true
    
    # Update với error handling
    printf "${GREEN}Đang cập nhật apt (có thể mất vài phút)...${RESET}\n"
    if apt update 2>&1 | grep -v "^W:" | grep -v "keyring"; then
        touch /root/.apt_updated
        printf "${GREEN}✓ APT đã sẵn sàng!${RESET}\n"
    else
        printf "${YELLOW}⚠ APT update có warnings, nhưng vẫn có thể dùng${RESET}\n"
        touch /root/.apt_updated
    fi
    
    printf "${GREEN}Sử dụng: apt install -y --no-install-recommends <package>${RESET}\n"
    printf "${YELLOW}Lưu ý:${RESET}\n"
    printf "  - Nếu gặp lỗi GPG: fix-apt-keys\n"
    printf "  - Nếu gặp lỗi dpkg: fix-dpkg-errors\n"
    printf "  - Nếu curl/wget lỗi SSL: fix-ssl-certs\n"
    printf "  - Nên dùng --no-install-recommends để tránh lỗi\n"
    
elif command -v apk &>/dev/null && [ ! -f /root/.apk_updated ]; then
    printf "${GREEN}Khởi tạo apk...${RESET}\n"
    apk update -q 2>/dev/null && touch /root/.apk_updated
    printf "${GREEN}Sử dụng: apk add <package>${RESET}\n"
    
elif command -v pacman &>/dev/null && [ ! -f /root/.pacman_updated ]; then
    printf "${GREEN}Khởi tạo pacman...${RESET}\n"
    pacman-key --init &>/dev/null && pacman-key --populate &>/dev/null && touch /root/.pacman_updated
    printf "${GREEN}Sử dụng: pacman -S <package>${RESET}\n"
fi

printf "\n${CYAN}Gõ 'exit' để thoát${RESET}\n\n"
export PS1='\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\# '

# Detect shell - Alpine uses /bin/sh, others use /bin/bash
if [ -f /bin/bash ]; then
    exec /bin/bash --norc
else
    exec /bin/sh
fi
STARTUP_EOF
    chmod +x "$ROOTFS_DIR/root/.startup.sh"
}

# =============================
# KHỞI ĐỘNG FAKE ROOT
# =============================
start_fake_root() {
    print_info "Đang khởi động fake root environment..."
    
    # Validate
    [ ! -x "$PROOT_BIN" ] && { print_error "proot không khả dụng"; exit 1; }
    [ ! -d "$ROOTFS_DIR" ] && { print_error "Rootfs không tồn tại"; exit 1; }
    
    create_startup_script
    display_complete
    
    # Khởi động proot với cấu hình tối ưu
    # Chỉ bind resolv.conf nếu file tồn tại trên host
    local bind_args=()
    bind_args+=("--rootfs=$ROOTFS_DIR")
    bind_args+=("--root-id")
    bind_args+=("--cwd=/root")
    bind_args+=("--bind=/dev")
    bind_args+=("--bind=/sys")
    bind_args+=("--bind=/proc")
    
    # Bind resolv.conf nếu tồn tại
    if [ -f "/etc/resolv.conf" ]; then
        bind_args+=("--bind=/etc/resolv.conf")
    else
        print_warn "Host không có /etc/resolv.conf, bỏ qua bind"
    fi
    
    bind_args+=("--kill-on-exit")
    
    # Detect shell - Alpine uses /bin/sh, others use /bin/bash
    if [ -f "$ROOTFS_DIR/bin/bash" ]; then
        bind_args+=("/bin/bash")
    else
        bind_args+=("/bin/sh")
    fi
    
    bind_args+=("/root/.startup.sh")
    
    exec "$PROOT_BIN" "${bind_args[@]}"
}

# =============================
# XÓA ROOTFS
# =============================
uninstall_rootfs() {
    [ ! -d "$ROOTFS_DIR" ] && { print_info "Rootfs chưa được cài đặt"; return 0; }
    
    print_warn "CẢNH BÁO: Xóa toàn bộ rootfs tại $ROOTFS_DIR"
    [ -f "$ROOTFS_DIR/.distro_name" ] && cat "$ROOTFS_DIR/.distro_name"
    
    read -p "Xác nhận xóa? (yes/no): " confirm
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')  # Case insensitive
    if [ "$confirm" != "yes" ] && [ "$confirm" != "y" ]; then
        print_info "Hủy xóa"
        return 0
    fi
    
    print_info "Đang xóa..."
    rm -rf "$ROOTFS_DIR" && print_info "Xóa thành công!" || print_error "Xóa thất bại"
}

# =============================
# HIỂN THỊ HELP
# =============================
show_help() {
    cat << EOF
${COLOR_BLUE}PRoot Fake Root Environment v${SCRIPT_VERSION}${COLOR_RESET}

${COLOR_GREEN}Sử dụng:${COLOR_RESET}
  $0 [option]

${COLOR_GREEN}Options:${COLOR_RESET}
  -h, --help          Hiển thị trợ giúp
  -i, --install       Cài đặt rootfs mới
  -s, --start         Khởi động fake root (mặc định)
  -u, --uninstall     Xóa rootfs
  -r, --reinstall     Cài đặt lại rootfs

${COLOR_GREEN}Tính năng:${COLOR_RESET}
  ✅ Giả lập môi trường root hoàn chỉnh
  ✅ Hỗ trợ 7 distro: Ubuntu (24.04, 22.04, 20.04), Debian (12, 11), Alpine, Arch
  ✅ Sử dụng apt/apk/pacman bình thường
  ✅ Không cần quyền root thật
  ✅ Tự động retry và fallback khi download

${COLOR_GREEN}Ví dụ:${COLOR_RESET}
  $0                  # Khởi động (auto-install nếu chưa cài)
  $0 -i               # Cài đặt rootfs mới
  $0 -r               # Cài lại từ đầu
  FAKEROOT_DIR=/custom/path $0  # Dùng thư mục tùy chỉnh

${COLOR_GREEN}Bên trong fake root:${COLOR_RESET}
  apt update && apt install -y --no-install-recommends vim python3 nodejs
  apk add curl wget git
  pacman -Syu base-devel

${COLOR_YELLOW}Xử lý lỗi (Ubuntu/Debian):${COLOR_RESET}
  Lỗi GPG "NO_PUBKEY":
    1. Chạy: fix-apt-keys
    2. Hoặc: apt update --allow-insecure-repositories
  
  Lỗi dpkg "Sub-process /usr/bin/dpkg returned an error code (1)":
    1. Chạy: fix-dpkg-errors
    2. Hoặc: apt install -y --no-install-recommends <package>
    3. Hoặc: dpkg --configure -a && apt install -f
EOF
}

# =============================
# MAIN
# =============================
validate_environment() {
    local missing_tools=()
    
    # Kiểm tra tar (bắt buộc)
    if ! command -v tar &>/dev/null; then
        missing_tools+=("tar")
    fi
    
    # Kiểm tra wget HOẶC curl (ít nhất 1 cái)
    if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
        missing_tools+=("wget or curl")
    fi
    
    # Kiểm tra file command (optional but useful)
    if ! command -v file &>/dev/null; then
        print_warn "Lệnh 'file' không có, một số kiểm tra sẽ bị bỏ qua"
    fi
    
    # Report missing tools
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Thiếu các lệnh: ${missing_tools[*]}"
        print_error "Vui lòng cài đặt: sudo apt install ${missing_tools[*]// or / }"
        exit 1
    fi
    
    # Kiểm tra disk space
    local available_space=$(df -P "$HOME" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 1048576 ]; then  # Less than 1GB
        print_warn "Dung lượng đĩa thấp: $(( available_space / 1024 ))MB. Nên có ít nhất 1GB."
    fi
    
    # Thông báo tool sẽ dùng
    if command -v wget &>/dev/null; then
        print_info "Sử dụng wget để download"
    else
        print_info "Sử dụng curl để download"
    fi
}

main() {
    validate_environment
    
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -u|--uninstall)
            uninstall_rootfs
            exit 0
            ;;
        -r|--reinstall)
            uninstall_rootfs
            # Fallthrough bằng cách gọi lại với -i
            set -- "-i" "--and-start"
            ;;
        -i|--install)
            print_banner
            check_architecture
            download_proot || exit 1
            choose_distro || exit 1
            install_rootfs || exit 1
            
            # Nếu có flag --and-start thì tiếp tục start, nếu không thì exit
            if [ "${2:-}" = "--and-start" ]; then
                start_fake_root
            else
                print_info "Cài đặt hoàn tất! Chạy '$0' để khởi động"
                exit 0
            fi
            ;;
        -s|--start|"")
            # Auto-install nếu chưa cài
            if [ ! -f "$ROOTFS_DIR/.installed" ]; then
                print_warn "Chưa cài đặt rootfs, bắt đầu cài đặt..."
                print_banner
                check_architecture
                download_proot || exit 1
                choose_distro
                install_rootfs || exit 1
            fi
            
            # Kiểm tra proot
            [ ! -x "$PROOT_BIN" ] && {
                check_architecture
                download_proot || exit 1
            }
            
            start_fake_root
            ;;
        *)
            print_error "Tùy chọn không hợp lệ: $1"
            show_help
            exit 1
            ;;
    esac
}

# Chạy main
main "$@"