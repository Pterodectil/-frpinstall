#!/bin/sh

# =========================================
# OpenWrt FRP Auto Installer
# =========================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear

echo "====================================="
echo "     OpenWrt FRP Installer"
echo "====================================="
echo ""

# =========================================
# ROOT CHECK
# =========================================

if [ "$(id -u)" -ne 0 ]; then
    echo "${RED}[!] Run script as root${NC}"
    exit 1
fi

# =========================================
# INTERNET CHECK
# =========================================

echo "${YELLOW}[*] Checking internet connection...${NC}"

ping -c 1 github.com >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "${RED}[!] No internet connection${NC}"
    exit 1
fi

echo "${GREEN}[+] Internet OK${NC}"

# =========================================
# INPUT
# =========================================

echo ""
printf "VPS IP: "
read VPS_IP

printf "FRP Token: "
read FRP_TOKEN

printf "Router Name: "
read ROUTER_NAME

printf "SSH Port (example 6001): "
read SSH_PORT

printf "LuCI Port (example 7001): "
read LUCI_PORT

# =========================================
# ARCH DETECTION
# =========================================

echo ""
echo "${YELLOW}[*] Detecting architecture...${NC}"

ARCH_INFO=$(opkg print-architecture)

if echo "$ARCH_INFO" | grep -q "aarch64"; then
    FRP_ARCH="arm64"

elif echo "$ARCH_INFO" | grep -q "arm"; then
    FRP_ARCH="arm"

elif echo "$ARCH_INFO" | grep -q "mipsel"; then
    FRP_ARCH="mipsle"

elif echo "$ARCH_INFO" | grep -q "mips"; then
    FRP_ARCH="mips"

elif echo "$ARCH_INFO" | grep -q "x86_64"; then
    FRP_ARCH="amd64"

else
    echo "${RED}[!] Unsupported architecture${NC}"
    echo "$ARCH_INFO"
    exit 1
fi

echo "${GREEN}[+] Using architecture: ${FRP_ARCH}${NC}"

# =========================================
# INSTALL PACKAGES
# =========================================

echo ""
echo "${YELLOW}[*] Installing packages...${NC}"

opkg update
opkg install wget-ssl tar gzip

# =========================================
# CLEANUP OLD INSTALL
# =========================================

echo ""
echo "${YELLOW}[*] Cleaning old installation...${NC}"

killall frpc 2>/dev/null

rm -rf /root/frp
rm -f /root/frp_*.tar.gz

# =========================================
# DOWNLOAD FRP
# =========================================

FRP_VERSION="0.61.1"

cd /root || exit

echo ""
echo "${YELLOW}[*] Downloading FRP ${FRP_VERSION}...${NC}"

wget https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz

if [ $? -ne 0 ]; then
    echo "${RED}[!] Download failed${NC}"
    exit 1
fi

echo "${GREEN}[+] Download completed${NC}"

# =========================================
# EXTRACT
# =========================================

echo ""
echo "${YELLOW}[*] Extracting archive...${NC}"

tar -xzf frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz

mv frp_${FRP_VERSION}_linux_${FRP_ARCH} frp

cd /root/frp || exit

chmod +x frpc

echo "${GREEN}[+] Extraction completed${NC}"

# =========================================
# CREATE CONFIG
# =========================================

echo ""
echo "${YELLOW}[*] Creating FRP config...${NC}"

cat > /root/frp/frpc.toml <<EOF
serverAddr = "${VPS_IP}"
serverPort = 7000

auth.method = "token"
auth.token = "${FRP_TOKEN}"

transport.tcpMux = true

[[proxies]]
name = "${ROUTER_NAME}-ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = ${SSH_PORT}

[[proxies]]
name = "${ROUTER_NAME}-luci"
type = "tcp"
localIP = "127.0.0.1"
localPort = 80
remotePort = ${LUCI_PORT}
EOF

echo "${GREEN}[+] Config created${NC}"

# =========================================
# CREATE SERVICE
# =========================================

echo ""
echo "${YELLOW}[*] Creating service...${NC}"

cat > /etc/init.d/frpc <<'EOF'
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {

    procd_open_instance

    procd_set_param command /root/frp/frpc -c /root/frp/frpc.toml

    procd_set_param respawn

    procd_close_instance
}
EOF

chmod +x /etc/init.d/frpc

echo "${GREEN}[+] Service created${NC}"

# =========================================
# ENABLE SERVICE
# =========================================

echo ""
echo "${YELLOW}[*] Starting FRP service...${NC}"

/etc/init.d/frpc enable
/etc/init.d/frpc restart

sleep 5

# =========================================
# STATUS CHECK
# =========================================

echo ""
echo "${YELLOW}[*] Checking FRP process...${NC}"

if ps | grep frpc | grep -v grep >/dev/null; then
    echo "${GREEN}[+] FRP started successfully${NC}"
else
    echo "${RED}[!] FRP failed to start${NC}"
    exit 1
fi

# =========================================
# DONE
# =========================================

echo ""
echo "====================================="
echo "${GREEN} Installation completed${NC}"
echo "====================================="
echo ""

echo "SSH:"
echo "ssh root@${VPS_IP} -p ${SSH_PORT}"
echo ""

echo "LuCI:"
echo "http://${VPS_IP}:${LUCI_PORT}"
echo ""

echo "FRP Config:"
echo "/root/frp/frpc.toml"
echo ""

echo "Service:"
echo "/etc/init.d/frpc"
echo ""

echo "Restart FRP:"
echo "/etc/init.d/frpc restart"
echo ""
