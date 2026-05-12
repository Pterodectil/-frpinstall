#!/bin/sh

clear

echo "====================================="
echo "     OpenWrt FRP Installer"
echo "====================================="
echo ""

# =========================================
# ROOT CHECK
# =========================================

if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Run script as root"
    exit 1
fi

# =========================================
# INTERNET CHECK
# =========================================

echo "[*] Checking internet connection..."

ping -c 1 github.com >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "[!] No internet connection"
    exit 1
fi

echo "[+] Internet OK"

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
echo "[*] Detecting architecture..."

ARCH="$(uname -m)"

echo "[*] uname -m: $ARCH"

FRP_ARCH=""

case "$ARCH" in

    x86_64)
        FRP_ARCH="amd64"
        ;;

    aarch64|arm64)
        FRP_ARCH="arm64"
        ;;

    arm*|armv7l)
        FRP_ARCH="arm"
        ;;

    mipsel*|mipsle*)
        FRP_ARCH="mipsle"
        ;;

    mips*)
        FRP_ARCH="mips"
        ;;

esac

if [ -z "$FRP_ARCH" ]; then
    echo "[!] Unsupported architecture: $ARCH"
    exit 1
fi

echo "[+] Using architecture: $FRP_ARCH"
# =========================================
# INSTALL PACKAGES
# =========================================

echo ""
echo "[*] Installing packages..."

opkg update
opkg install wget-ssl tar gzip

# =========================================
# CLEANUP OLD INSTALL
# =========================================

echo ""
echo "[*] Cleaning old installation..."

killall frpc 2>/dev/null

rm -rf /root/frp
rm -f /root/frp_*.tar.gz

# =========================================
# DOWNLOAD FRP
# =========================================

FRP_VERSION="0.61.1"

cd /root || exit

echo ""
echo "[*] Downloading FRP $FRP_VERSION..."

wget https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz

if [ $? -ne 0 ]; then
    echo "[!] Download failed"
    exit 1
fi

echo "[+] Download completed"

# =========================================
# EXTRACT
# =========================================

echo ""
echo "[*] Extracting archive..."

tar -xzf frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz

mv frp_${FRP_VERSION}_linux_${FRP_ARCH} frp

cd /root/frp || exit

chmod +x frpc

echo "[+] Extraction completed"

# =========================================
# CREATE CONFIG
# =========================================

echo ""
echo "[*] Creating FRP config..."

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

echo "[+] Config created"

# =========================================
# CREATE SERVICE
# =========================================

echo ""
echo "[*] Creating service..."

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

echo "[+] Service created"

# =========================================
# ENABLE SERVICE
# =========================================

echo ""
echo "[*] Starting FRP service..."

/etc/init.d/frpc enable
/etc/init.d/frpc restart

sleep 5

# =========================================
# STATUS CHECK
# =========================================

echo ""
echo "[*] Checking FRP process..."

if ps | grep frpc | grep -v grep >/dev/null; then
    echo "[+] FRP started successfully"
else
    echo "[!] FRP failed to start"
    exit 1
fi

# =========================================
# DONE
# =========================================

echo ""
echo "====================================="
echo " Installation completed"
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
