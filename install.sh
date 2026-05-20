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
echo "   FRP OpenWrt Installer v1.3"
echo "=================================="
echo

# Dependencies
for CMD in wget tar pidof
do
    if ! command -v "$CMD" >/dev/null 2>&1
    then
        echo "Missing dependency: $CMD"
        exit 1
    fi
done

# Existing install
INSTALLED=0

[ -f "$INSTALL_DIR/frpc" ] && INSTALLED=1
[ -f "$CONFIG" ] && INSTALLED=1
[ -f "/etc/init.d/frpc" ] && INSTALLED=1

if [ "$INSTALLED" -eq 1 ]
then
    echo "FRP installation found"
    echo
    echo "1) Reinstall"
    echo "2) Exit"
    echo

    printf "Choice: "
    read CHOICE

    case "$CHOICE" in

        1)
            if [ -f /etc/init.d/frpc ]
            then
                /etc/init.d/frpc stop >/dev/null 2>&1
                /etc/init.d/frpc disable >/dev/null 2>&1
            fi

            PID=$(pidof frpc)

            if [ -n "$PID" ]
            then
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

printf "VPS IP/domain: "
read VPS

if [ -z "$VPS" ]
then
    echo "Empty VPS"
    exit 1
fi

printf "FRP token: "
read TOKEN

if [ -z "$TOKEN" ]
then
    echo "Empty token"
    exit 1
fi

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

mkdir -p "$TMP_DIR"

cd "$TMP_DIR" || exit 1

FILE="frp_${VERSION}_${FRP_ARCH}.tar.gz"

echo
echo "Downloading..."

wget -q \
"https://github.com/fatedier/frp/releases/download/v${VERSION}/${FILE}" \
-O frp.tar.gz

if [ $? -ne 0 ]
then
    echo "
