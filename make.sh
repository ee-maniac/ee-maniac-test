#!/bin/bash
set -e

# ===== USER CONFIGURATION =====
# Replace this URL with the direct raw link to your uploaded tarball
CUSTOM_TARBALL_URL="https://raw.githubusercontent.com/ee-maniac/ee-maniac-test/main/GooseRelayVPN-server-v1.7.1-linux-amd64.tar.gz"
# =============================

INSTALL_DIR="/root/goose"
SERVICE_NAME="goose-relay"
BINARY_NAME="goose-server"
CONFIG_NAME="server_config.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
fi

# Create install directory
mkdir -p "$INSTALL_DIR"

# Generate fresh config if not exists
if [ ! -f "$INSTALL_DIR/$CONFIG_NAME" ]; then
    echo -e "${YELLOW}Creating fresh configuration...${NC}"
    curl -s "https://raw.githubusercontent.com/Kianmhz/GooseRelayVPN/main/server_config.example.json" -o "$INSTALL_DIR/$CONFIG_NAME"
    TUNNEL_KEY=$(openssl rand -hex 32)
    jq --arg key "$TUNNEL_KEY" '.tunnel_key = $key' "$INSTALL_DIR/$CONFIG_NAME" > "$INSTALL_DIR/$CONFIG_NAME.tmp" && mv "$INSTALL_DIR/$CONFIG_NAME.tmp" "$INSTALL_DIR/$CONFIG_NAME"
    echo -e "${GREEN}Generated tunnel_key: $TUNNEL_KEY${NC}"

    echo -e "\nRoute all outbound connections through a local SOCKS5 proxy? (Cloudflare WARP)"
    read -p "Activate upstream_proxy? (y/n): " use_proxy
    if [[ "$use_proxy" == "y" ]]; then
        jq '.upstream_proxy = "socks5://127.0.0.1:40000"' "$INSTALL_DIR/$CONFIG_NAME" > "$INSTALL_DIR/$CONFIG_NAME.tmp" && mv "$INSTALL_DIR/$CONFIG_NAME.tmp" "$INSTALL_DIR/$CONFIG_NAME"
    else
        jq 'del(.upstream_proxy)' "$INSTALL_DIR/$CONFIG_NAME" > "$INSTALL_DIR/$CONFIG_NAME.tmp" && mv "$INSTALL_DIR/$CONFIG_NAME.tmp" "$INSTALL_DIR/$CONFIG_NAME"
    fi
fi

# Download tarball from custom URL (no checksum)
echo -e "${YELLOW}Downloading from $CUSTOM_TARBALL_URL ...${NC}"
curl -fL -o "/tmp/goose.tar.gz" "$CUSTOM_TARBALL_URL"

# Extract binary
tar -xzf "/tmp/goose.tar.gz" -C "$INSTALL_DIR"
rm /tmp/goose.tar.gz

# Ensure binary is named correctly
if [ ! -f "$INSTALL_DIR/$BINARY_NAME" ]; then
    FIND_BIN=$(find "$INSTALL_DIR" -name "$BINARY_NAME" -type f | head -n 1)
    [ -n "$FIND_BIN" ] && mv "$FIND_BIN" "$INSTALL_DIR/$BINARY_NAME"
fi
chmod +x "$INSTALL_DIR/$BINARY_NAME"

# Create systemd service
cat <<EOF > /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=GooseRelayVPN exit server
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BINARY_NAME -config $INSTALL_DIR/$CONFIG_NAME
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# Firewall (optional)
PORT=$(jq -r '.server_port // 8443' "$INSTALL_DIR/$CONFIG_NAME")
if command -v ufw &> /dev/null; then
    ufw allow "$PORT"/tcp
elif command -v iptables &> /dev/null; then
    iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
fi

echo -e "${GREEN}GooseRelayVPN server installed.${NC}"
systemctl status "$SERVICE_NAME" --no-pager
