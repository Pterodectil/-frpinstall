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
echo "   FRP OpenWrt Installer v1.2"
echo "=================================="
echo

################################
# Dependencies
################################

for CMD in wget tar pidof
do
    if ! command -v "$CMD" >/dev/null 2>&1
    then
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

################################
# Input
################################

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
echo "Unsupported architecture:"
echo "$ARCH"
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

if [ $? -ne 0 ]
then
echo "Download failed"
exit 1
fi

echo "Extracting..."

tar -xzf frp.tar.gz

if [ $? -ne 0 ]
then
echo "Extract failed"
exit 1
fi

DIR="frp_${VERSION}_${FRP_ARCH}"

if [ ! -f "$DIR/frpc" ]
then
echo "frpc binary missing"
exit 1
fi

cp "$DIR/frpc" "$INSTALL_DIR/" || {
echo "Copy failed"
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

################################
# Mode
################################

echo
echo "Select mode:"
echo "1) SSH + LuCI preset"
echo "2) Custom ports"
echo

printf "Choice: "
read MODE

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
echo "Port 7000 reserved for FRP"
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
localIP = "127.0.0.1"
localPort = ${LPORT}
remotePort = ${LUCIPORT}
EOF

COUNT=2
;;

2)

while true
do

echo

printf "Connection name: "
read NAME

printf "Router local port: "
read LPORT

printf "VPS remote port: "
read RPORT

case "$RPORT" in
7000)
echo "Port 7000 reserved"
continue
;;
esac

case " $USED_PORTS " in
*" $RPORT "*)
echo "Port already used"
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

printf "Add another? (y/n): "
read ADD

[ "$ADD" != "y" ] && break

done
;;

*)

echo "Invalid option"
exit 1
;;

esac

[ "$COUNT" -eq 0 ] && exit 1

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

if [ "$AUTO" = "y" ]
then
/etc/init.d/frpc enable
fi

/etc/init.d/frpc stop >/dev/null 2>&1
/etc/init.d/frpc start

sleep 3

echo

PID=$(pidof frpc)

if [ -n "$PID" ]
then
echo "FRP running (
