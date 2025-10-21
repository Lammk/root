#!/bin/bash
set -euo pipefail

# =============================
# PROOT FAKE ROOT ENVIRONMENT
# Tạo môi trường root giả lập với proot
# Có thể sử dụng apt và các công cụ system
# =============================

ROOTFS_DIR="$HOME/.fakeroot-proot"
PROOT_BIN="$HOME/.local/bin/proot"
MAX_RETRIES=50
TIMEOUT=10
ARCH=$(uname -m)

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
    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $1"
}

print_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"
}

print_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1"
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
    case "$ARCH" in
        x86_64)
            ARCH_ALT="amd64"
            ;;
        aarch64|arm64)
            ARCH_ALT="arm64"
            ;;
        armv7l|armhf)
            ARCH_ALT="armhf"
            ;;
        i386|i686)
            ARCH_ALT="i386"
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
    print_info "Đang tải proot cho $ARCH..."
    
    mkdir -p "$(dirname "$PROOT_BIN")"
    
    # Thử nhiều nguồn proot
    local PROOT_URLS=(
        "https://raw.githubusercontent.com/foxytouxxx/freeroot/main/proot-${ARCH}"
        "https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-${ARCH}-static"
        "https://github.com/termux/proot/releases/latest/download/proot-${ARCH}"
    )
    
    for url in "${PROOT_URLS[@]}"; do
        print_info "Đang thử tải từ: $url"
        if wget --tries=$MAX_RETRIES --timeout=$TIMEOUT --no-hsts -O "$PROOT_BIN" "$url" 2>/dev/null; then
            if [ -s "$PROOT_BIN" ]; then
                chmod +x "$PROOT_BIN"
                print_info "Tải proot thành công!"
                return 0
            fi
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
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v4.0.1/debian-${ARCH_ALT}-pd-v4.0.1.tar.xz"
            ;;
        5)
            DISTRO_NAME="Debian 11"
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v3.10.0/debian-${ARCH_ALT}-pd-v3.10.0.tar.xz"
            ;;
        6)
            DISTRO_NAME="Alpine Linux"
            ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/${ARCH}/alpine-minirootfs-3.18.0-${ARCH}.tar.gz"
            ;;
        7)
            DISTRO_NAME="Arch Linux"
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v4.0.1/archlinux-${ARCH_ALT}-pd-v4.0.1.tar.xz"
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
    print_info "Đang tải rootfs từ: $ROOTFS_URL"
    local ROOTFS_FILE="/tmp/rootfs_$$.tar.gz"
    
    if ! wget --tries=$MAX_RETRIES --timeout=$TIMEOUT --no-hsts -O "$ROOTFS_FILE" "$ROOTFS_URL"; then
        print_error "Không thể tải rootfs"
        return 1
    fi
    
    # Giải nén
    print_info "Đang giải nén rootfs..."
    if [[ "$ROOTFS_FILE" == *.tar.xz ]]; then
        tar -xJf "$ROOTFS_FILE" -C "$ROOTFS_DIR" 2>/dev/null || tar -xf "$ROOTFS_FILE" -C "$ROOTFS_DIR"
    else
        tar -xzf "$ROOTFS_FILE" -C "$ROOTFS_DIR" 2>/dev/null || tar -xf "$ROOTFS_FILE" -C "$ROOTFS_DIR"
    fi
    
    rm -f "$ROOTFS_FILE"
    
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
    mkdir -p "$ROOTFS_DIR"/{dev,sys,proc,tmp,root,home}
    
    # Đánh dấu đã cài đặt
    touch "$ROOTFS_DIR/.installed"
    echo "$DISTRO_NAME" > "$ROOTFS_DIR/.distro_name"
    
    print_info "Cài đặt $DISTRO_NAME hoàn tất!"
}

# =============================
# TẠO SCRIPT KHỞI ĐỘNG
# =============================
create_startup_script() {
    cat > "$ROOTFS_DIR/root/.startup.sh" << 'STARTUP_EOF'
#!/bin/bash

# Màu sắc
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

clear
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║                                                      ║${RESET}"
echo -e "${CYAN}║           CHÀO MỪNG ĐẾN FAKE ROOT!                 ║${RESET}"
echo -e "${CYAN}║                                                      ║${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${GREEN}Thông tin hệ thống:${RESET}"
echo -e "  OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo 'Unknown')"
echo -e "  Kernel: $(uname -r)"
echo -e "  Arch: $(uname -m)"
echo -e "  User: $(whoami) (UID: $(id -u))"
echo ""
echo -e "${YELLOW}Bạn đang ở trong môi trường fake root với proot${RESET}"
echo -e "${YELLOW}Có thể sử dụng: apt, dpkg, và các công cụ system${RESET}"
echo ""

# Cập nhật apt nếu là Ubuntu/Debian
if command -v apt &>/dev/null; then
    if [ ! -f /root/.apt_updated ]; then
        echo -e "${GREEN}Đang cập nhật apt lần đầu...${RESET}"
        apt update 2>/dev/null || true
        touch /root/.apt_updated
    fi
    echo -e "${GREEN}Để cài đặt packages: apt install <package>${RESET}"
fi

# Cập nhật apk nếu là Alpine
if command -v apk &>/dev/null; then
    if [ ! -f /root/.apk_updated ]; then
        echo -e "${GREEN}Đang cập nhật apk...${RESET}"
        apk update 2>/dev/null || true
        touch /root/.apk_updated
    fi
    echo -e "${GREEN}Để cài đặt packages: apk add <package>${RESET}"
fi

# Cập nhật pacman nếu là Arch
if command -v pacman &>/dev/null; then
    if [ ! -f /root/.pacman_updated ]; then
        echo -e "${GREEN}Đang khởi tạo pacman keyring...${RESET}"
        pacman-key --init 2>/dev/null || true
        pacman-key --populate 2>/dev/null || true
        touch /root/.pacman_updated
    fi
    echo -e "${GREEN}Để cài đặt packages: pacman -S <package>${RESET}"
fi

echo ""
echo -e "${CYAN}Gõ 'exit' để thoát${RESET}"
echo ""

# Set prompt màu đỏ cho root
export PS1='\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\# '

# Chạy bash
exec /bin/bash --norc
STARTUP_EOF
    
    chmod +x "$ROOTFS_DIR/root/.startup.sh"
}

# =============================
# KHỞI ĐỘNG FAKE ROOT
# =============================
start_fake_root() {
    print_info "Đang khởi động fake root environment..."
    
    # Tạo script khởi động
    create_startup_script
    
    # Kiểm tra proot
    if [ ! -x "$PROOT_BIN" ]; then
        print_error "proot không tồn tại hoặc không thể thực thi"
        exit 1
    fi
    
    display_complete
    
    # Khởi động proot
    exec "$PROOT_BIN" \
        --rootfs="$ROOTFS_DIR" \
        --root-id \
        --cwd="/root" \
        --bind=/dev \
        --bind=/sys \
        --bind=/proc \
        --bind=/etc/resolv.conf \
        --kill-on-exit \
        /bin/bash /root/.startup.sh
}

# =============================
# XÓA ROOTFS
# =============================
uninstall_rootfs() {
    print_warn "CẢNH BÁO: Điều này sẽ xóa toàn bộ rootfs!"
    read -p "Bạn có chắc chắn muốn xóa? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        print_info "Đang xóa rootfs..."
        rm -rf "$ROOTFS_DIR"
        print_info "Đã xóa rootfs!"
    else
        print_info "Hủy thao tác xóa"
    fi
}

# =============================
# HIỂN THỊ HELP
# =============================
show_help() {
    cat << EOF
${COLOR_BLUE}PRoot Fake Root Environment${COLOR_RESET}

Sử dụng:
  $0 [option]

Options:
  -h, --help          Hiển thị trợ giúp
  -i, --install       Cài đặt rootfs mới
  -s, --start         Khởi động fake root (mặc định)
  -u, --uninstall     Xóa rootfs
  -r, --reinstall     Cài đặt lại rootfs

Tính năng:
  ✅ Giả lập môi trường root hoàn chỉnh
  ✅ Có thể sử dụng apt/dpkg
  ✅ Cài đặt packages như bình thường
  ✅ Hỗ trợ nhiều distro (Ubuntu, Debian, Alpine, Arch)
  ✅ Không cần quyền root thật

Ví dụ:
  $0                  # Khởi động fake root
  $0 --install        # Cài đặt rootfs mới
  $0 --uninstall      # Xóa rootfs

Sau khi vào fake root:
  apt update          # Cập nhật packages
  apt install vim     # Cài đặt vim
  apt install python3 # Cài đặt python
EOF
}

# =============================
# MAIN
# =============================
main() {
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
            print_banner
            check_architecture
            download_proot
            choose_distro
            install_rootfs
            start_fake_root
            ;;
        -i|--install)
            print_banner
            check_architecture
            download_proot
            choose_distro
            install_rootfs
            print_info "Cài đặt hoàn tất! Chạy '$0' để khởi động"
            exit 0
            ;;
        -s|--start|"")
            # Kiểm tra đã cài đặt chưa
            if [ ! -f "$ROOTFS_DIR/.installed" ]; then
                print_warn "Chưa cài đặt rootfs"
                print_info "Đang bắt đầu cài đặt..."
                print_banner
                check_architecture
                download_proot
                choose_distro
                install_rootfs
            fi
            
            # Kiểm tra proot
            if [ ! -x "$PROOT_BIN" ]; then
                print_warn "proot chưa được cài đặt"
                check_architecture
                download_proot
            fi
            
            start_fake_root
            ;;
        *)
            print_error "Tùy chọn không hợp lệ: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"