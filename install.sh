#!/bin/sh

clear

INSTALL_DIR="/root/frp"
TMP_DIR="/tmp/frp_install"
CONFIG="$INSTALL_DIR/frpc.toml"
VERSION="0.65.0"

cleanup() {
    rm -rf "$TMP_DIR" >/dev/null 2>&1
}

trap cleanup EXIT

echo "=================================="
echo "   FRP OpenWrt Installer v1.0"
echo "=================================="
echo

################################
# Dependencies
################################

for CMD in wget tar grep pidof; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "Missing dependency: $CMD"
        exit 1
    fi
done

################################
# Existing installation
################################

INSTALLED=0

[ -f "$INSTALL_DIR/frpc" ] && INSTALLED=1
[ -f "$CONFIG" ] && INSTALLED=1
[ -f "/etc/init.d/frpc" ] && INSTALLED=1

if [ "$INSTALLED" -eq 1 ]; then

    echo "Existing FRP installation found"
    echo
    echo "1) Reinstall"
    echo "2) Exit"
    echo

    printf "Choice: "
    read CHOICE

    case "$CHOICE" in
        1)

            echo
            echo "Removing old installation..."

            if [ -f /etc/init.d/frpc ]; then
                /etc/init.d/frpc stop >/dev/null 2>&1
                /etc/init.d/frpc disable >/dev/null 2>&1
            fi

            PID=$(pidof frpc)

            if [ -n "$PID" ]; then
                kill $PID >/dev/null 2>&1
            fi

            rm -f /etc/init.d/frpc
            rm -rf "$INSTALL_DIR"

            echo "Done"
            ;;
        *)
            exit 0
            ;;
    esac
fi

mkdir -p "$INSTALL_DIR"

################################
# User input
################################

printf "VPS IP/domain: "
read VPS

if [ -z "$VPS" ]; then
    echo "VPS cannot be empty"
    exit 1
fi

printf "FRP token: "
read TOKEN

if [ -z "$TOKEN" ]; then
    echo "Token cannot be empty"
    exit 1
fi

################################
# Architecture
################################

ARCH=$(uname -m)

if command -v opkg >/dev/null 2>&1; then
    OPKG_ARCH=$(opkg print-architecture | awk '{print $2}')
else
    OPKG_ARCH=""
fi

case "$ARCH" in

aarch64|aarch64_generic)
    FRP_ARCH="linux_arm64"
;;

armv7*|armv6*|armv8l)
    FRP_ARCH="linux_arm"
;;

x86_64)
    FRP_ARCH="linux_amd64"
;;

mipsel*)
    FRP_ARCH="linux_mipsle"
;;

mips*)
    FRP_ARCH="linux_mips"
;;

*)
    echo
    echo "Unsupported architecture:"
    echo "$ARCH"
    echo "$OPKG_ARCH"
    exit 1
;;

esac

################################
# Download
################################

mkdir -p "$TMP_DIR"

cd "$TMP_DIR" || exit 1

FILE="frp_${VERSION}_${FRP_ARCH}.tar.gz"

echo
echo "Downloading FRP..."

wget -q \
"https://github.com/fatedier/frp/releases/download/v${VERSION}/${FILE}" \
-O frp.tar.gz

if [ $? -ne 0 ]; then
    echo "Download failed"
    exit 1
fi

echo "Extracting..."

tar -xzf frp.tar.gz

if [ $? -ne 0 ]; then
    echo "Extraction failed"
    exit 1
fi

DIR="frp_${VERSION}_${FRP_ARCH}"

if [ ! -f "$DIR/frpc" ]; then
    echo "frpc binary not found"
    exit 1
fi

cp "$DIR/frpc" "$INSTALL_DIR/" || {
    echo "Failed to copy frpc"
    exit 1
}

chmod +x "$INSTALL_DIR/frpc"

################################
# Config
################################

cat > "$CONFIG" <<EOF
serverAddr = "${VPS}"
serverPort = 7000

auth.method = "token"
auth.token = "${TOKEN}"
EOF

COUNT=0
USED_PORTS=""

while true
do

echo

printf "Connection name: "
read NAME

[ -z "$NAME" ] && continue

printf "Router local port: "
read LPORT

printf "VPS remote port: "
read RPORT

case "$LPORT" in
*[!0-9]*|"")
    echo "Invalid local port"
    continue
;;
esac

case "$RPORT" in
*[!0-9]*|"")
    echo "Invalid remote port"
    continue
;;
esac

if [ "$LPORT" -lt 1 ] || [ "$LPORT" -gt 65535 ]; then
    echo "Local port out of range"
    continue
fi

if [ "$RPORT" -lt 1 ] || [ "$RPORT" -gt 65535 ]; then
    echo "Remote port out of range"
    continue
fi

case " $USED_PORTS " in
*" $RPORT "*)
    echo "Remote port already used"
    continue
;;
esac

USED_PORTS="$USED_PORTS $RPORT"

cat >> "$CONFIG" <<EOF

[[proxies]]
name = "${NAME}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${LPORT}
remotePort = ${RPORT}
EOF

COUNT=$((COUNT+1))

printf "Add another port? (y/n): "
read ADD

[ "$ADD" != "y" ] && break

done

if [ "$COUNT" -eq 0 ]; then
    echo "No ports configured"
    exit 1
fi

################################
# Service
################################

cat >/etc/init.d/frpc <<'EOF'
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command \
        /root/frp/frpc \
        -c \
        /root/frp/frpc.toml
    procd_set_param respawn
    procd_close_instance
}
EOF

chmod +x /etc/init.d/frpc

printf "Enable autostart? (y/n): "
read AUTO

if [ "$AUTO" = "y" ]; then
    /etc/init.d/frpc enable
fi

/etc/init.d/frpc stop >/dev/null 2>&1
/etc/init.d/frpc start

sleep 5

echo

PID=$(pidof frpc)

if [ -n "$PID" ]; then
    echo "FRP running (PID: $PID)"
else
    echo "FRP failed"
    echo
    logread | tail -20
fi

echo
echo "Config: $CONFIG"
