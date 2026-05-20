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
echo "   FRP OpenWrt Installer v2.0"
echo "=================================="
echo

# Dependencies
for CMD in wget tar pidof
do
    command -v "$CMD" >/dev/null 2>&1 || {
        echo "Missing dependency: $CMD"
        exit 1
    }
done

# Existing install
if [ -f "$INSTALL_DIR/frpc" ] || [ -f "/etc/init.d/frpc" ]
then
    echo "FRP installation found"
    echo "1) Reinstall"
    echo "2) Exit"

    printf "Choice: "
    read CHOICE

    if [ "$CHOICE" = "1" ]
    then

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

        rm -rf "$INSTALL_DIR"
        rm -f /etc/init.d/frpc

    else
        exit 0
    fi
fi

mkdir -p "$INSTALL_DIR"
mkdir -p "$TMP_DIR"

printf "VPS IP/domain: "
read VPS

[ -z "$VPS" ] && {
    echo "Empty VPS"
    exit 1
}

printf "FRP token: "
read TOKEN

[ -z "$TOKEN" ] && {
    echo "Empty token"
    exit 1
}

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

cd "$TMP_DIR" || exit 1

FILE="frp_${VERSION}_${FRP_ARCH}.tar.gz"

echo
echo "Downloading..."

wget -q \
"https://github.com/fatedier/frp/releases/download/v${VERSION}/${FILE}" \
-O frp.tar.gz

if [ $? -ne 0 ]
then
    echo "Download failed"
    exit 1
fi

echo "Extracting..."

tar -xzf frp.tar.gz || exit 1

DIR="frp_${VERSION}_${FRP_ARCH}"

if [ ! -f "$DIR/frpc" ]
then
    echo "frpc not found"
    exit 1
fi

cp "$DIR/frpc" "$INSTALL_DIR/frpc" || exit 1
chmod +x "$INSTALL_DIR/frpc"

cat > "$CONFIG" <<EOF
serverAddr = "$VPS"
serverPort = 7000

auth.method = "token"
auth.token = "$TOKEN"
EOF

echo
echo "1) SSH + LuCI preset"
echo "2) Custom"

printf "Choice: "
read MODE

if [ "$MODE" = "1" ]
then

    printf "SSH external port: "
    read SSHPORT

    printf "LuCI external port: "
    read LUCIPORT

cat >> "$CONFIG" <<EOF

[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $SSHPORT

[[proxies]]
name = "luci"
type = "tcp"
localIP = "127.0.0.1"
localPort = 80
remotePort = $LUCIPORT
EOF

else

while true
do

printf "Connection name: "
read NAME

printf "Local port: "
read LPORT

printf "Remote port: "
read RPORT

[ "$RPORT" = "7000" ] && {
    echo "7000 reserved"
    continue
}

cat >> "$CONFIG" <<EOF

[[proxies]]
name = "$NAME"
type = "tcp"
localIP = "127.0.0.1"
localPort = $LPORT
remotePort = $RPORT
EOF

printf "Add another? (y/n): "
read ADD

[ "$ADD" != "y" ] && break

done

fi

cat >/etc/init.d/frpc <<'EOF'
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

printf "Enable autostart? (y/n): "
read AUTO

if [ "$AUTO" = "y" ]
then
    /etc/init.d/frpc enable
fi

/etc/init.d/frpc stop >/dev/null 2>&1
/etc/init.d/frpc start

sleep 3

PID=$(pidof frpc)

echo

if [ -n "$PID" ]
then
    echo "FRP running (PID: $PID)"
else
    echo "FRP failed"
fi

echo
echo "Config: $CONFIG"
