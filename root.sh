#!/bin/bash
set -euo pipefail

# =============================
# PROOT FAKE ROOT ENVIRONMENT
# Tạo môi trường root giả lập với proot
# Có thể sử dụng apt và các công cụ system
# =============================

# Cấu hình
ROOTFS_DIR="${FAKEROOT_DIR:-$HOME/.fakeroot-proot}"
PROOT_BIN="$HOME/.local/bin/proot"
MAX_RETRIES=3
TIMEOUT=30
ARCH=$(uname -m)
ALPINE_ARCH=""

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
    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $1" >&2
}

print_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1" >&2
}

print_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1" >&2
}

# Cleanup khi exit
cleanup() {
    local exit_code=$?
    [ -n "${ROOTFS_FILE:-}" ] && rm -f "$ROOTFS_FILE" "${ROOTFS_FILE%.xz}" "${ROOTFS_FILE%.gz}" 2>/dev/null
    return $exit_code
}
trap cleanup EXIT INT TERM

# Download file với retry
download_file() {
    local url="$1"
    local output="$2"
    local retries="${3:-$MAX_RETRIES}"
    
    for ((i=1; i<=retries; i++)); do
        if wget --tries=1 --timeout=$TIMEOUT --no-hsts --show-progress -q -O "$output" "$url" 2>&1; then
            [ -s "$output" ] && return 0
        fi
        [ $i -lt $retries ] && print_warn "Thử lại ($i/$retries)..."
        sleep 1
    done
    return 1
}

# Giải nén file tar
extract_tar() {
    local file="$1"
    local dest="$2"
    
    print_info "Đang giải nén $(basename "$file")..."
    
    # Tự động phát hiện và giải nén
    if tar -xf "$file" -C "$dest" 2>/dev/null; then
        return 0
    fi
    
    # Fallback: thử giải nén thủ công
    case "$file" in
        *.tar.xz)
            print_warn "Thử giải nén với xz..."
            xz -d "$file" && tar -xf "${file%.xz}" -C "$dest"
            ;;
        *.tar.gz)
            print_warn "Thử giải nén với gzip..."
            gzip -d "$file" && tar -xf "${file%.gz}" -C "$dest"
            ;;
        *)
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
    [ -n "${ARCH_ALT:-}" ] && return 0
    
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
    echo ""
    echo -e "${COLOR_BLUE}Chọn distro Linux muốn cài đặt:${COLOR_RESET}"
    echo ""
    echo "1) Ubuntu 24.04 LTS (Noble)"
    echo "2) Ubuntu 22.04 LTS (Jammy)"
    echo "3) Ubuntu 20.04 LTS (Focal)"
    echo "4) Debian 12 (Bookworm)"
    echo "5) Debian 11 (Bullseye)"
    echo "6) Alpine Linux (nhẹ nhất)"
    echo "7) Arch Linux"
    echo ""
    read -p "Nhập lựa chọn (1-7) [mặc định: 1]: " distro_choice
    distro_choice=${distro_choice:-1}
    
    case $distro_choice in
        1)
            DISTRO_NAME="Ubuntu 24.04"
            ROOTFS_URL="http://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04-base-${ARCH_ALT}.tar.gz"
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
            DISTRO_NAME="Debian 12"
            # Debian sử dụng amd64, arm64, armhf, i386
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v4.13.0/debian-${ARCH_ALT}-pd-v4.13.0.tar.xz"
            ;;
        5)
            DISTRO_NAME="Debian 11"
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v4.13.0/debian-${ARCH_ALT}-pd-v4.13.0.tar.xz"
            ;;
        6)
            DISTRO_NAME="Alpine Linux"
            ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/${ALPINE_ARCH}/alpine-minirootfs-3.19.1-${ALPINE_ARCH}.tar.gz"
            ;;
        7)
            DISTRO_NAME="Arch Linux"
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v4.13.0/archlinux-${ARCH_ALT}-pd-v4.13.0.tar.xz"
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
    
    # Xác định extension từ URL
    ROOTFS_FILE="/tmp/rootfs_$$.${ROOTFS_URL##*.}"
    [[ "$ROOTFS_URL" == *.tar.* ]] && ROOTFS_FILE="/tmp/rootfs_$$.tar.${ROOTFS_URL##*.tar.}"
    
    # Tải với fallback
    if ! download_file "$ROOTFS_URL" "$ROOTFS_FILE"; then
        print_error "Không thể tải rootfs chính"
        
        # URL dự phòng
        case "$DISTRO_NAME" in
            "Alpine Linux")
                print_info "Thử Alpine 3.18.4..."
                ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/${ALPINE_ARCH}/alpine-minirootfs-3.18.4-${ALPINE_ARCH}.tar.gz"
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
    mkdir -p "$ROOTFS_DIR"/{dev,sys,proc,tmp,root,home,var/log}
    
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
# TẠO SCRIPT KHỞI ĐỘNG
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
    apt update -qq 2>/dev/null && touch /root/.apt_updated
    printf "${GREEN}Sử dụng: apt install <package>${RESET}\n"
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
exec /bin/bash --norc
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
    exec "$PROOT_BIN" \
        --rootfs="$ROOTFS_DIR" \
        --root-id \
        --cwd="/root" \
        --bind=/dev \
        --bind=/sys \
        --bind=/proc \
        --bind="/etc/resolv.conf" \
        --kill-on-exit \
        /bin/bash /root/.startup.sh
}

# =============================
# XÓA ROOTFS
# =============================
uninstall_rootfs() {
    [ ! -d "$ROOTFS_DIR" ] && { print_info "Rootfs chưa được cài đặt"; return 0; }
    
    print_warn "CẢNH BÁO: Xóa toàn bộ rootfs tại $ROOTFS_DIR"
    [ -f "$ROOTFS_DIR/.distro_name" ] && cat "$ROOTFS_DIR/.distro_name"
    
    read -p "Xác nhận xóa? (yes/no): " confirm
    [ "$confirm" != "yes" ] && { print_info "Hủy xóa"; return 0; }
    
    print_info "Đang xóa..."
    rm -rf "$ROOTFS_DIR" && print_info "Xóa thành công!" || print_error "Xóa thất bại"
}

# =============================
# HIỂN THỊ HELP
# =============================
show_help() {
    cat << EOF
${COLOR_BLUE}PRoot Fake Root Environment${COLOR_RESET}

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
  apt update && apt install vim python3 nodejs
  apk add curl wget git
  pacman -Syu base-devel
EOF
}

# =============================
# MAIN
# =============================
validate_environment() {
    # Kiểm tra các lệnh cần thiết
    local required_cmds=("wget" "tar")
    for cmd in "${required_cmds[@]}"; do
        command -v "$cmd" &>/dev/null || {
            print_error "Thiếu lệnh: $cmd. Vui lòng cài đặt."
            exit 1
        }
    done
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
            ;& # Fallthrough
        -i|--install)
            print_banner
            check_architecture
            download_proot || exit 1
            choose_distro
            install_rootfs || exit 1
            
            [ "${1:-}" = "-i" ] && {
                print_info "Cài đặt hoàn tất! Chạy '$0' để khởi động"
                exit 0
            }
            start_fake_root
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