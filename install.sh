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
echo "   FRP OpenWrt Installer v1.1"
echo "=================================="
echo

################################
# Dependencies
################################

for CMD in wget tar pidof; do
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

    echo "FRP installation found"
    echo
    echo "1) Reinstall"
    echo "2) Exit"
    echo

    printf "Choice: "
    read CHOICE

    case "$CHOICE" in

    1)

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

        echo "Old installation removed"
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

[ -z "$VPS" ] && exit 1

printf "FRP token: "
read TOKEN

[ -z "$TOKEN" ] && exit 1

################################
# Architecture
################################

ARCH=$(uname -m)

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
    echo "Unsupported architecture: $ARCH"
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
echo "Downloading..."

wget -q \
"https://github.com/fatedier/frp/releases/download/v${VERSION}/${FILE}" \
-O frp.tar.gz || {

echo "Download failed"
exit 1

}

tar -xzf frp.tar.gz || {

echo "Extract failed"
exit 1

}

DIR="frp_${VERSION}_${FRP_ARCH}"

cp "$DIR/frpc" "$INSTALL_DIR/" || {

echo "Copy failed"
exit 1

}

chmod +x "$INSTALL_DIR/frpc"

################################
# Base config
################################

cat > "$CONFIG" <<EOF
serverAddr = "${VPS}"
serverPort = 7000

auth.method = "token"
auth.token = "${TOKEN}"
EOF

################################
# Port setup
################################

echo
echo "Select mode:"
echo "1) SSH + LuCI preset"
echo "2) Custom ports"
echo

printf "Choice: "
read MODE

COUNT=0
USED=""

case "$MODE" in

1)

printf "SSH external port: "
read SSHPORT

printf "LuCI external port: "
read LUCIPORT

echo
echo "LuCI type:"
echo "1) HTTP (80)"
echo "2) HTTPS (443)"

printf "Choice: "
read LMODE

case "$LMODE" in
2)
LPORT=443
;;
*)
LPORT=80
;;
esac

for PORT in "$SSHPORT" "$LUCIPORT"
do

case "$PORT" in
*[!0-9]*|"")
echo "Invalid port"
exit 1
;;
esac

if [ "$PORT" -eq 7000 ]
then
echo "7000 reserved for FRP"
exit 1
fi

done

cat >> "$CONFIG" <<EOF

[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = ${SSHPORT}

[[proxies]]
name = "luci"
type = "tcp"
localIP
