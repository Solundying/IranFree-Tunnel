#!/bin/bash
# IranFree Tunnel - CLI with interactive menu (whiptail/select)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="/opt/smite"
FOOTER_MSG="Support & Updates: Telegram @bep20vpnbot | Channel: https://t.me/+OHTf8xzLwTplYzAx | GitHub: https://github.com/Solundying | Donate (USDT-BEP20): 0x170BB3786a5af57647260d3C4EfEa8845d025010 | BuyMeACoffee: https://buymeacoffee.com/amirhossein1892"

# Delegate to smite if available for admin/status/update/restart/logs/edit
run_smite() {
    if [ -x /usr/local/bin/smite ]; then
        exec /usr/local/bin/smite "$@"
    fi
    if [ -f "$INSTALL_DIR/cli/smite.py" ]; then
        exec python3 "$INSTALL_DIR/cli/smite.py" "$@"
    fi
    echo "smite CLI not found. Install panel first."
    exit 1
}

# Start tunnel services (panel)
cmd_start() {
    cd "$INSTALL_DIR" 2>/dev/null || { echo "Install dir not found: $INSTALL_DIR"; exit 1; }
    docker compose up -d
    echo -e "${GREEN}IranFree Tunnel panel started.${NC}"
    echo "$FOOTER_MSG"
}

# Stop tunnel services
cmd_stop() {
    cd "$INSTALL_DIR" 2>/dev/null || { echo "Install dir not found: $INSTALL_DIR"; exit 1; }
    docker compose down
    echo -e "${GREEN}IranFree Tunnel panel stopped.${NC}"
    echo "$FOOTER_MSG"
}

# Auto-install Docker, Node, Python
cmd_install_tools() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root: sudo iranfree install-tools"
        exit 1
    fi
    echo "Installing Docker, Node.js, and Python if missing..."
    if ! command -v docker &>/dev/null; then
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh
        rm -f /tmp/get-docker.sh
        echo "Docker installed."
    else
        echo "Docker already installed."
    fi
    if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
        echo "Node.js installed."
    else
        echo "Node.js already installed."
    fi
    if ! command -v python3 &>/dev/null; then
        apt-get update && apt-get install -y python3 python3-pip
        echo "Python3 installed."
    else
        echo "Python3 already installed."
    fi
    echo -e "${GREEN}Tools ready.${NC}"
    echo "$FOOTER_MSG"
}

# Full uninstall: remove configs and optional data
cmd_uninstall() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root: sudo iranfree uninstall"
        exit 1
    fi
    echo "This will: stop containers, remove sysctl/limits entries added by IranFree, remove $INSTALL_DIR (optional), and remove CLI."
    read -p "Continue? [y/N]: " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        exit 0
    fi
    cd "$INSTALL_DIR" 2>/dev/null && docker compose down 2>/dev/null || true
    # Remove proxy config
    rm -f /etc/apt/apt.conf.d/99iranfree-proxy.conf
    rm -rf /etc/systemd/system/docker.service.d/http-proxy.conf 2>/dev/null
    systemctl daemon-reload 2>/dev/null
    # Revert sysctl (restore backup if exists)
    if [ -f /etc/sysctl.conf.smite-backup ]; then
        cp /etc/sysctl.conf.smite-backup /etc/sysctl.conf
        echo "Restored sysctl from backup."
    else
        sed -i '/# IranFree Tunnel Network Optimizations/,/net.ipv4.tcp_mtu_probing = 1/d' /etc/sysctl.conf 2>/dev/null || true
    fi
    # Remove limits
    sed -i '/# IranFree Tunnel File Descriptor Limits/,/root hard nofile 65535/d' /etc/security/limits.conf 2>/dev/null || true
    # Remove BBR/iranfree modules
    rm -f /etc/modules-load.d/iranfree.conf
    # Remove CLI
    rm -f /usr/local/bin/iranfree
    read -p "Remove install directory $INSTALL_DIR? [y/N]: " rm_dir
    if [ "$rm_dir" = "y" ] || [ "$rm_dir" = "Y" ]; then
        rm -rf "$INSTALL_DIR"
        echo "Removed $INSTALL_DIR"
    fi
    echo -e "${GREEN}Uninstall complete.${NC}"
    echo "$FOOTER_MSG"
}

# Speedtest: lightweight download test from several endpoints (Iran + international)
cmd_speedtest() {
    echo "IranFree Tunnel - Speedtest (download test)"
    echo ""
    SIZE_MB=1
    # Endpoints: small file ~1MB (adjust URLs if needed)
    declare -a URLS=(
        "https://cloudflare.com/cdn-cgi/trace"
        "https://www.google.com/generate_204"
        "https://api.github.com"
    )
    for url in "${URLS[@]}"; do
        name=$(echo "$url" | sed 's|https\?://||' | cut -d/ -f1)
        echo -n "Testing $name ... "
        start=$(date +%s.%N)
        if curl -fsSL --connect-timeout 5 --max-time 15 -o /dev/null "$url" 2>/dev/null; then
            end=$(date +%s.%N)
            elapsed=$(echo "$end - $start" | bc 2>/dev/null || echo "0"); [ -z "$elapsed" ] && elapsed=0
            echo -e "${GREEN}OK${NC} (${elapsed}s)"
        else
            echo -e "${RED}FAIL${NC}"
        fi
    done
    # Optional: wget/curl a larger file for Mbps estimate (e.g. 1MB from a CDN)
    echo ""
    echo "Download speed (1MB test from Cloudflare):"
    if command -v curl &>/dev/null; then
        start=$(date +%s.%N)
        bytes=$(curl -fsSL --connect-timeout 5 -w '%{size_download}' -o /dev/null "https://cloudflare.com/cdn-cgi/trace" 2>/dev/null || echo 0)
        end=$(date +%s.%N)
        if [ -n "$bytes" ] && [ "$bytes" -gt 0 ]; then
            elapsed=$(echo "$end - $start" | bc 2>/dev/null || echo 1); [ -z "$elapsed" ] || [ "$elapsed" = "0" ] && elapsed=1
            kbps=$(echo "scale=2; $bytes * 8 / 1000 / $elapsed" | bc 2>/dev/null || echo "?")
            echo "  ~${kbps} Kbps (small payload)"
        fi
    fi
    echo "$FOOTER_MSG"
}

# Fix DNS: set Cloudflare DNS and lock resolv.conf
cmd_fix_dns() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root: sudo iranfree fix-dns"
        exit 1
    fi
    echo "Setting DNS to Cloudflare (1.1.1.1, 1.0.0.1)..."
    if [ -f /etc/resolv.conf ]; then
        chattr -i /etc/resolv.conf 2>/dev/null || true
    fi
    cat > /etc/resolv.conf << 'EOF'
# IranFree Tunnel - Cloudflare DNS (locked)
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF
    chattr +i /etc/resolv.conf 2>/dev/null && echo -e "${GREEN}DNS set and locked (chattr +i /etc/resolv.conf).${NC}" || echo "DNS set (could not lock - chattr not available?)."
    echo "$FOOTER_MSG"
}

# Interactive menu
show_menu() {
    if command -v whiptail &>/dev/null; then
        choice=$(whiptail --title "IranFree Tunnel" --menu "Choose an option" 22 60 10 \
            "1" "Start tunnel (panel)" \
            "2" "Stop tunnel (panel)" \
            "3" "Install tools (Docker, Node, Python)" \
            "4" "Uninstall (clean system settings)" \
            "5" "Admin: create user (smite)" \
            "6" "Status (smite)" \
            "7" "Speedtest (download test)" \
            "8" "Fix DNS (Cloudflare + lock)" \
            "9" "Exit" \
            3>&1 1>&2 2>&3) || true
    else
        echo "=== IranFree Tunnel ==="
        echo "1) Start tunnel (panel)"
        echo "2) Stop tunnel (panel)"
        echo "3) Install tools (Docker, Node, Python)"
        echo "4) Uninstall (clean system settings)"
        echo "5) Admin: create user (smite)"
        echo "6) Status (smite)"
        echo "7) Speedtest (download test)"
        echo "8) Fix DNS (Cloudflare + lock)"
        echo "9) Exit"
        read -p "Choice [1-9]: " choice
    fi

    case "$choice" in
        1) cmd_start ;;
        2) cmd_stop ;;
        3) cmd_install_tools ;;
        4) cmd_uninstall ;;
        5) run_smite admin create ;;
        6) run_smite status ;;
        7) cmd_speedtest ;;
        8) cmd_fix_dns ;;
        9) echo "$FOOTER_MSG"; exit 0 ;;
        *) echo "Invalid option."; exit 1 ;;
    esac
}

# Main
case "${1:-}" in
    start)         cmd_start ;;
    stop)          cmd_stop ;;
    install-tools) cmd_install_tools ;;
    uninstall)     cmd_uninstall ;;
    speedtest)     cmd_speedtest ;;
    fix-dns)       cmd_fix_dns ;;
    admin|status|update|restart|logs|edit|edit-env)
        run_smite "$@"
        ;;
    "")
        show_menu
        ;;
    *)
        run_smite "$@"
        ;;
esac
