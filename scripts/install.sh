#!/bin/bash
# IranFree Tunnel - Panel Installer (optimized for Iran/bootstrap)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Footer message for end of script
IRANFREE_FOOTER() {
    echo ""
    echo "--- IranFree Tunnel ---"
    echo "Support & Updates: Telegram @bep20vpnbot | Channel: https://t.me/+OHTf8xzLwTplYzAx"
    echo "GitHub: https://github.com/Solundying"
    echo "Donate (Crypto/USDT-BEP20): 0x170BB3786a5af57647260d3C4EfEa8845d025010"
    echo "BuyMeACoffee: https://buymeacoffee.com/amirhossein1892"
    echo ""
}

# Spinner function
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Progress function
progress() {
    echo -e "${GREEN}✓${NC} $1"
}

echo "=== IranFree Tunnel - Panel Installer ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Enable Docker BuildKit for faster builds
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Detect OS and arch
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64) GOST_ARCH="amd64" ;;
    aarch64|arm64) GOST_ARCH="arm64" ;;
    *) GOST_ARCH="amd64" ;;
esac

# --- Iran / Bootstrap: optional proxy and Gost v3 pre-download ---
USE_PROXY="${IRANFREE_USE_PROXY:-}"
if [ -z "$USE_PROXY" ]; then
    read -p "Install from Iran / behind filter? Need proxy for APT and Docker? [y/N]: " USE_PROXY_INPUT
    USE_PROXY="${USE_PROXY_INPUT:-n}"
fi
if [ "$USE_PROXY" = "y" ] || [ "$USE_PROXY" = "Y" ] || [ "$USE_PROXY" = "1" ]; then
    export USE_PROXY=1
    if [ -z "${HTTP_PROXY:-}" ] && [ -z "${HTTPS_PROXY:-}" ]; then
        read -p "Enter HTTP proxy (e.g. http://127.0.0.1:8080 or leave empty): " HTTP_PROXY_INPUT
        if [ -n "$HTTP_PROXY_INPUT" ]; then
            export HTTP_PROXY="$HTTP_PROXY_INPUT"
            export HTTPS_PROXY="${HTTPS_PROXY:-$HTTP_PROXY_INPUT}"
            export http_proxy="$HTTP_PROXY"
            export https_proxy="$HTTPS_PROXY"
        fi
    fi
    if [ -n "${HTTP_PROXY:-}" ]; then
        progress "Using proxy for this session: $HTTP_PROXY"
        # APT proxy
        if [ -d /etc/apt/apt.conf.d ]; then
            echo "Acquire::http::Proxy \"$HTTP_PROXY\";" > /etc/apt/apt.conf.d/99iranfree-proxy.conf
            echo "Acquire::https::Proxy \"${HTTPS_PROXY:-$HTTP_PROXY}\";" >> /etc/apt/apt.conf.d/99iranfree-proxy.conf
        fi
        # Docker daemon proxy (will be applied after Docker is installed)
        mkdir -p /etc/systemd/system/docker.service.d
        cat > /etc/systemd/system/docker.service.d/http-proxy.conf << DOCKERPROXY
[Service]
Environment="HTTP_PROXY=$HTTP_PROXY"
Environment="HTTPS_PROXY=${HTTPS_PROXY:-$HTTP_PROXY}"
Environment="NO_PROXY=localhost,127.0.0.1"
DOCKERPROXY
    fi
fi

# Download Gost v3 binary from mirror (works even with limited connectivity)
GOST_VERSION="3.2.6"
GOST_BIN_DIR="/opt/iranfree-gost"
mkdir -p "$GOST_BIN_DIR"
GOST_BIN="$GOST_BIN_DIR/gost"
GOST_URL_DIRECT="https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_linux_${GOST_ARCH}.tar.gz"
GOST_URL_MIRROR1="https://ghproxy.com/${GOST_URL_DIRECT}"
GOST_URL_MIRROR2="https://mirror.ghproxy.com/${GOST_URL_DIRECT}"
if [ ! -x "$GOST_BIN" ]; then
    echo "Downloading Gost v${GOST_VERSION} binary..."
    for GOST_URL in "$GOST_URL_DIRECT" "$GOST_URL_MIRROR1" "$GOST_URL_MIRROR2"; do
        if curl -fsSL --connect-timeout 15 "$GOST_URL" -o /tmp/gost.tar.gz 2>/dev/null; then
            tar -xzf /tmp/gost.tar.gz -C /tmp
            GOST_EXTRACTED="$(find /tmp -maxdepth 2 -type f -name 'gost' 2>/dev/null | head -n1)"
            if [ -n "$GOST_EXTRACTED" ] && [ -f "$GOST_EXTRACTED" ]; then
                install -Dm755 "$GOST_EXTRACTED" "$GOST_BIN"
                rm -f /tmp/gost.tar.gz
                progress "Gost v3 binary installed to $GOST_BIN"
                break
            fi
        fi
        rm -f /tmp/gost.tar.gz
    done
    if [ ! -x "$GOST_BIN" ]; then
        echo -e "${YELLOW}Warning: Could not download Gost v3. Panel will try to use image or system gost.${NC}"
    fi
fi
# Ensure panel can use this binary (symlink if /usr/local/bin not yet in image)
if [ -x "$GOST_BIN" ]; then
    ln -sf "$GOST_BIN" /usr/local/bin/gost 2>/dev/null || true
fi

# Install git if not present
if ! command -v git &> /dev/null; then
    echo "Installing git..."
    apt-get update -qq && apt-get install -y git > /dev/null 2>&1
    progress "Git installed"
fi

# Install Node.js and npm if not present
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    echo "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt-get install -y nodejs > /dev/null 2>&1
    progress "Node.js installed"
fi

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh > /dev/null 2>&1
    rm get-docker.sh
    progress "Docker installed"
fi
# Apply Docker proxy and reload if we set it earlier
if [ -n "${USE_PROXY:-}" ] && [ "$USE_PROXY" = "1" ] && [ -n "${HTTP_PROXY:-}" ] && [ -d /etc/systemd/system/docker.service.d ]; then
    systemctl daemon-reload
    systemctl restart docker 2>/dev/null || true
fi

# Check docker-compose
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}docker-compose not found. Please install it separately${NC}"
    exit 1
fi

# Get installation directory
INSTALL_DIR="/opt/smite"
echo "Installing to: $INSTALL_DIR (IranFree Tunnel)"

# Clone or update repository
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    echo "IranFree Tunnel already installed in $INSTALL_DIR"
    cd "$INSTALL_DIR"
    # Update if needed
    if [ -d ".git" ]; then
        echo "Updating repository..."
        git pull --quiet || true
    fi
else
    # Clone from GitHub
    echo "Cloning IranFree Tunnel repository from GitHub..."
    rm -rf "$INSTALL_DIR"
    GIT_BRANCH=""
    if [ "${SMITE_VERSION:-latest}" = "next" ]; then
        GIT_BRANCH="-b next"
    fi
    git clone --depth 1 $GIT_BRANCH https://github.com/zZedix/Smite.git "$INSTALL_DIR" || {
        echo -e "${RED}Error: Failed to clone repository${NC}"
        exit 1
    }
    cd "$INSTALL_DIR"
    progress "Repository cloned"
fi

# Minimal configuration prompts (only essential)
echo ""
echo "Configuration:"
read -p "Panel port (default: 8000): " PANEL_PORT
PANEL_PORT=${PANEL_PORT:-8000}

# Ask about domain and HTTPS
echo ""
read -p "Do you want to use a domain with HTTPS? [y/N]: " USE_DOMAIN
USE_DOMAIN=${USE_DOMAIN:-n}

DOMAIN=""
DOMAIN_EMAIL=""
NGINX_ENABLED="false"
SMITE_HTTP_PORT="80"
SMITE_HTTPS_PORT="443"

if [ "$USE_DOMAIN" = "y" ] || [ "$USE_DOMAIN" = "Y" ]; then
    read -p "Enter your domain name (e.g., panel.example.com): " DOMAIN
    if [ -n "$DOMAIN" ]; then
        read -p "Enter your email for Let's Encrypt notifications: " DOMAIN_EMAIL
        if [ -z "$DOMAIN_EMAIL" ]; then
            echo -e "${YELLOW}Email is required for Let's Encrypt.${NC}"
            read -p "Enter your email for Let's Encrypt notifications: " DOMAIN_EMAIL
        fi
        if [ -n "$DOMAIN_EMAIL" ]; then
            NGINX_ENABLED="true"
            read -p "HTTP port for the panel (default: 80): " SMITE_HTTP_PORT_INPUT
            SMITE_HTTP_PORT=${SMITE_HTTP_PORT_INPUT:-80}
            read -p "HTTPS port for the panel (default: 443): " SMITE_HTTPS_PORT_INPUT
            SMITE_HTTPS_PORT=${SMITE_HTTPS_PORT_INPUT:-443}
            echo "HTTPS will be automatically configured with Let's Encrypt"
        else
            echo -e "${YELLOW}Warning: Email is required for Let's Encrypt. HTTPS setup skipped.${NC}"
        fi
    else
        echo -e "${YELLOW}Warning: No domain provided. HTTPS setup skipped.${NC}"
    fi
fi

# Database type is always SQLite
DB_TYPE=sqlite

# Create .env file
cat > .env << EOF
PANEL_PORT=$PANEL_PORT
PANEL_HOST=0.0.0.0
HTTPS_ENABLED=${NGINX_ENABLED}
PANEL_DOMAIN=${DOMAIN}
SMITE_HTTP_PORT=${SMITE_HTTP_PORT}
SMITE_HTTPS_PORT=${SMITE_HTTPS_PORT}
SMITE_SSL_DOMAIN=${DOMAIN}
DOCS_ENABLED=true
SMITE_VERSION=${SMITE_VERSION:-latest}

DB_TYPE=$DB_TYPE
DB_PATH=./data/smite.db

SECRET_KEY=$(openssl rand -hex 32)
EOF

progress "Configuration saved"

# Create necessary directories
mkdir -p panel/data panel/certs
progress "Directories created"

# Apply network optimizations for stable tunnels
echo ""
echo "Applying network optimizations..."
if [ -f "/etc/sysctl.conf" ]; then
    # Backup original sysctl.conf
    if [ ! -f "/etc/sysctl.conf.smite-backup" ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.smite-backup
    fi
    
    # Add network optimizations if not already present
    if ! grep -q "# IranFree Tunnel Network Optimizations" /etc/sysctl.conf; then
        cat >> /etc/sysctl.conf << 'EOF'

# IranFree Tunnel Network Optimizations (Iran traffic)
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.udp_mem = 3145728 4194304 16777216
net.ipv4.ip_forward = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
EOF
        # Apply optimizations
        sysctl -p > /dev/null 2>&1 || true
        progress "Network optimizations applied"
    else
        progress "Network optimizations already applied"
    fi
fi

# Increase file descriptor limits
if [ -f "/etc/security/limits.conf" ]; then
    if ! grep -q "# IranFree Tunnel File Descriptor Limits" /etc/security/limits.conf; then
        cat >> /etc/security/limits.conf << 'EOF'

# IranFree Tunnel File Descriptor Limits
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
        progress "File descriptor limits increased"
    fi
    # Apply for current session
    ulimit -n 65535 2>/dev/null || true
fi

# Enable BBR congestion control (if available)
if modprobe -n tcp_bbr 2>/dev/null; then
    if ! grep -q "tcp_bbr" /etc/modules-load.d/*.conf 2>/dev/null && ! grep -q "tcp_bbr" /etc/modules 2>/dev/null; then
        echo "tcp_bbr" | tee -a /etc/modules-load.d/iranfree.conf > /dev/null 2>&1 || echo "tcp_bbr" >> /etc/modules 2>/dev/null || true
        modprobe tcp_bbr 2>/dev/null || true
        sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1 || true
        sysctl -w net.core.default_qdisc=fq > /dev/null 2>&1 || true
        progress "BBR congestion control enabled"
    else
        progress "BBR already applied"
    fi
fi
# BBR v3 / bbr2 (kernel 5.18+)
if modprobe -n tcp_bbr2 2>/dev/null; then
    if ! grep -q "tcp_bbr2" /etc/modules-load.d/*.conf 2>/dev/null; then
        echo "tcp_bbr2" | tee -a /etc/modules-load.d/iranfree.conf > /dev/null 2>&1 || true
        modprobe tcp_bbr2 2>/dev/null || true
        sysctl -w net.ipv4.tcp_congestion_control=bbr2 2>/dev/null || true
        progress "BBR v2/v3 (bbr2) enabled if supported"
    fi
fi

# Generate CA certificate placeholder if not exists
if [ ! -f "panel/certs/ca.crt" ]; then
    touch panel/certs/ca.crt panel/certs/ca.key
fi

# Install CLI (iranfree + smite for compatibility)
echo ""
echo "Installing CLI tools..."
if [ -f "cli/install_cli.sh" ]; then
    bash cli/install_cli.sh > /dev/null 2>&1
fi
if [ -f "scripts/iranfree.sh" ]; then
    cp scripts/iranfree.sh /usr/local/bin/iranfree
    chmod +x /usr/local/bin/iranfree
    progress "iranfree CLI installed"
elif [ -f "$INSTALL_DIR/scripts/iranfree.sh" ]; then
    cp "$INSTALL_DIR/scripts/iranfree.sh" /usr/local/bin/iranfree
    chmod +x /usr/local/bin/iranfree
    progress "iranfree CLI installed"
fi
if [ -f "cli/smite.py" ]; then
    cp cli/smite.py /usr/local/bin/smite 2>/dev/null || true
    chmod +x /usr/local/bin/smite 2>/dev/null || true
    progress "smite CLI (compat) installed"
fi

# Install minimal Python dependencies for CLI (if not in container)
if ! python3 -c "import requests" 2>/dev/null; then
    pip3 install requests --quiet 2>/dev/null || python3 -m pip install requests --quiet 2>/dev/null || true
fi

# Build frontend if needed (only if dist doesn't exist or is empty)
if [ -d "frontend" ]; then
    if [ ! -d "frontend/dist" ] || [ -z "$(ls -A frontend/dist 2>/dev/null)" ]; then
        echo ""
        echo "Building frontend..."
        cd frontend
        
        # Use npm ci for faster, reproducible builds
        echo "Installing frontend dependencies..."
        npm ci --silent --prefer-offline --no-audit --no-fund 2>/dev/null || npm install --silent --prefer-offline --no-audit --no-fund
        
        echo "Building frontend..."
        npm run build --silent
        
        if [ ! -d "dist" ] || [ -z "$(ls -A dist 2>/dev/null)" ]; then
            echo -e "${YELLOW}Warning: Frontend build failed. API will still be available at /api and /docs${NC}"
        else
            progress "Frontend built"
        fi
        cd ..
    else
        progress "Frontend already built"
    fi
fi

# Pull or build Docker images
echo ""
echo "Pulling Docker images from GitHub Container Registry..."
echo "  Using Docker BuildKit for faster builds..."

# Set version (default to latest, can be overridden with SMITE_VERSION env var)
if [ -z "${SMITE_VERSION}" ]; then
    export SMITE_VERSION=latest
fi

# Try to pull prebuilt images first (will fallback to build if not available)
echo "  Pulling prebuilt images from GHCR..."
if docker pull ghcr.io/zzedix/smite-panel:${SMITE_VERSION} 2>/dev/null; then
    progress "Panel image pulled from GHCR"
else
    echo -e "${YELLOW}Prebuilt image not found, will build locally...${NC}"
    echo "  Building images locally..."
    if docker compose build --parallel 2>&1; then
        progress "Docker images built locally"
    else
        echo -e "${YELLOW}Build completed with warnings${NC}"
    fi
fi

# Start services
echo ""
echo "Starting Smite Panel..."
if [ "$NGINX_ENABLED" = "true" ]; then
    # Start with nginx profile
    export NGINX_ENABLED=true
    
    # First start panel (will use host networking)
    docker compose up -d smite-panel
    
    # Wait a bit for panel to start
    echo "Waiting for panel to start..."
    sleep 5
    
    # Set up SSL certificates BEFORE starting nginx
    if [ -n "$DOMAIN" ] && [ -n "$DOMAIN_EMAIL" ]; then
        echo ""
        echo "Setting up SSL certificates..."
        chmod +x scripts/setup-ssl.sh
        bash scripts/setup-ssl.sh "$DOMAIN" "$DOMAIN_EMAIL" || {
            echo -e "${YELLOW}Warning: SSL setup had issues. You can configure it manually later.${NC}"
        }
        
        # Update nginx config with domain
        if [ -f "nginx/nginx.conf" ]; then
            sed -i "s/REPLACE_DOMAIN/$DOMAIN/g" nginx/nginx.conf 2>/dev/null || true
        fi
    fi
    
    # Now start nginx with https profile
    docker compose --profile https up -d nginx
    
    # Wait for nginx
    sleep 3
else
    # Start without nginx (direct access)
    docker compose up -d
fi

# Wait for services
echo "Waiting for services to start..."
sleep 5

# Check status
if docker ps | grep -q smite-panel; then
    echo ""
    echo -e "${GREEN}✅ IranFree Tunnel Panel installed successfully!${NC}"
    echo ""
    if [ "$NGINX_ENABLED" = "true" ] && [ -n "$DOMAIN" ]; then
        echo "Panel URL: https://$DOMAIN"
        echo "API Docs: https://$DOMAIN/docs"
        echo ""
        echo "Note: Make sure your domain DNS points to this server's IP address"
    else
        echo "Panel URL: http://localhost:$PANEL_PORT"
        echo "API Docs: http://localhost:$PANEL_PORT/docs"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Create admin user: iranfree admin create   (or: smite admin create)"
    if [ "$NGINX_ENABLED" = "true" ] && [ -n "$DOMAIN" ]; then
        echo "  2. Access the web interface at https://$DOMAIN"
    else
        echo "  2. Access the web interface at http://localhost:$PANEL_PORT"
    fi

    # UFW: allow only SSH, panel, and common tunnel ports
    if command -v ufw &>/dev/null; then
        echo ""
        read -p "Configure UFW firewall (allow SSH, panel, tunnel ports only)? [y/N]: " UFW_CONFIRM
        if [ "$UFW_CONFIRM" = "y" ] || [ "$UFW_CONFIRM" = "Y" ]; then
            ufw default deny incoming 2>/dev/null || true
            ufw default allow outgoing 2>/dev/null || true
            ufw allow 22/tcp comment 'SSH' 2>/dev/null || true
            ufw allow "${PANEL_PORT}/tcp" comment 'IranFree Panel' 2>/dev/null || true
            ufw allow 443/tcp comment 'HTTPS/Tunnel' 2>/dev/null || true
            ufw allow 8443/tcp comment 'Tunnel' 2>/dev/null || true
            ufw allow 8080/tcp comment 'Tunnel' 2>/dev/null || true
            ufw allow 7000/tcp comment 'FRP' 2>/dev/null || true
            ufw allow 23333/tcp comment 'Rathole' 2>/dev/null || true
            ufw allow 3080/tcp comment 'Backhaul' 2>/dev/null || true
            echo "y" | ufw enable 2>/dev/null || ufw --force enable 2>/dev/null || true
            progress "UFW configured (only SSH, panel, and tunnel ports open)"
        fi
    fi

    IRANFREE_FOOTER
else
    echo -e "${RED}❌ Installation completed but panel is not running${NC}"
    echo "Check logs with: docker compose logs"
    IRANFREE_FOOTER
    exit 1
fi
