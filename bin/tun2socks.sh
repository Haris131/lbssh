#!/bin/bash

# Tun2socks Wrapper
# by Lutfa Ilham
# v1.0.0

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

LBSSH_DIR="/root/lbssh"
CONFIG="${LBSSH_DIR}/config/config.json"
CONFIG_LB="$(grep SSH ${CONFIG} | awk '{print $1}' | sed 's/://g; s/"//g')"
TUN2SOCKS_MODE="$(grep 'legacy":' ${CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g')"
TUN_DEV="$(grep 'dev":' ${CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g')"
TUN_ADDRESS="$(grep 'address":' ${CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g')"
TUN_NETMASK="$(grep 'netmask":' ${CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g')"
TUN_GATEWAY="$(grep 'gateway":' ${CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g')"
TUN_MTU="$(grep 'mtu":' ${CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g')"
SOCKS_IP="$(grep 'ip":' ${CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '1p')"
SOCKS_PORT="$(grep 'port":' ${CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '1p')"
SOCKS_SERVER="${SOCKS_IP}:${SOCKS_PORT}"
UDPGW_IP="$(grep 'ip":' ${CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '2p')"
UDPGW_PORT="$(grep 'port":' ${CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '2p')"
UDPGW="${UDPGW_IP}:${UDPGW_PORT}"
GATEWAY="$(ip route | grep -v tun | awk '/default/ { print $3 }')"

function start_redsocks {
cat <<EOF> /etc/redsocks.conf
base {
	log_debug = off;
	log_info = off;
	redirector = iptables;
}
redsocks {
	local_ip = 0.0.0.0;
	local_port = 8123;
	ip = ${SOCKS_IP};
	port = ${SOCKS_PORT};
	type = socks5;
}
redsocks {
	local_ip = 127.0.0.1;
	local_port = 8124;
	ip = ${TUN_GATEWAY};
	port = ${SOCKS_PORT};
	type = socks5;
}
redudp {
	local_ip = ${UDPGW_IP}; 
	local_port = ${UDPGW_PORT};
	ip = ${TUN_GATEWAY};
	port = ${SOCKS_PORT};
	dest_ip = 8.8.8.8; 
	dest_port = 53; 
	udp_timeout = 30;
	udp_timeout_stream = 180;
}
dnstc {
	local_ip = 127.0.0.1;
	local_port = 5300;
}
EOF
sleep 1
iptables -t nat -N PROXY 2>/dev/null
iptables -t nat -I OUTPUT -j PROXY 2>/dev/null
iptables -t nat -A PREROUTING -i br-lan -p tcp -j PROXY
intranet=(127.0.0.0/8 192.168.0.0/16 0.0.0.0/8 10.0.0.0/8)
for subnet in ${intranet[@]} ; do
  iptables -t nat -A PROXY -d ${subnet} -j RETURN
done
iptables -t nat -A PROXY -p tcp -j REDIRECT --to-ports 8123
iptables -t nat -A PROXY -p tcp -j REDIRECT --to-ports 8124
iptables -t nat -A PROXY -p udp -j REDIRECT --to-ports ${UDPGW_PORT}
screen -AmdS redsocks redsocks -c /etc/redsocks.conf -p /var/run/redsocks.pid
echo -e "Redsocks started!"
}

function stop_redsocks {
kill $(screen -list | grep redsocks | awk -F '[.]' {'print $1'})
iptables -t nat -F OUTPUT 2>/dev/null
iptables -t nat -F PROXY 2>/dev/null
iptables -t nat -F PREROUTING 2>/dev/null
echo -e "Redsocks stopped!"
}

function start_tun {
if ifconfig "${TUN_DEV}" > /dev/null 2>&1; then
  ifconfig ${TUN_DEV} down
  ip tuntap del dev ${TUN_DEV} mode tun
fi
ip tuntap add dev ${TUN_DEV} mode tun
ifconfig ${TUN_DEV} mtu ${TUN_MTU}
echo -e "Tun device initialized!"
for CFG in ${CONFIG_LB}; do
  CFG_FILE="$(cat ${CONFIG} | jq .$CFG.config | awk '{print $1}' | sed 's/://g; s/"//g')"
  SERVER_IP="$(grep 'ip":' ${CFG_FILE} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '1p')"
  CDN_IP="$(grep 'ip":' ${CFG_FILE} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '3p')"
  ip route add ${SERVER_IP} via "${GATEWAY}" metric 4 > /dev/null 2>&1
  ip route add ${CDN_IP} via "${GATEWAY}" metric 4 > /dev/null 2>&1
done
ifconfig ${TUN_DEV} ${TUN_GATEWAY} netmask ${TUN_NETMASK} up
screen -AmdS badvpn-tun2socks badvpn-tun2socks --loglevel 0 --tundev ${TUN_DEV} --netif-ipaddr ${TUN_ADDRESS} --netif-netmask ${TUN_NETMASK} --socks-server-addr ${SOCKS_SERVER} --udpgw-remote-server-addr "${UDPGW}"
# removing default route
ip r | grep default > ${LBSSH_DIR}/log/route.log
ip route del $(cat ${LBSSH_DIR}/log/route.log)
# add default route to tun2socks
ip route add default via ${TUN_ADDRESS} metric 6
echo -e "Tun2socks started!"
}

function stop_tun {
kill $(screen -list | grep badvpn-tun2socks | awk -F '[.]' {'print $1'}) > /dev/null 2>&1
# recover default route
ip route add $(cat ${LBSSH_DIR}/log/route.log)
sleep 1
rm -rf ${LBSSH_DIR}/log/route.log
# remove default route to tun2socks
ip route del default via ${TUN_ADDRESS} metric 6
echo -e "Tun2socks stopped!"
for CFG in ${CONFIG_LB}; do
  CFG_FILE="$(cat ${CONFIG} | jq .$CFG.config | awk '{print $1}' | sed 's/://g; s/"//g')"
  SERVER_IP="$(grep 'ip":' ${CFG_FILE} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '1p')"
  CDN_IP="$(grep 'ip":' ${CFG_FILE} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '3p')"
  ip route del "${SERVER_IP}" > /dev/null 2>&1
  ip route del "${CDN_IP}" > /dev/null 2>&1
done
ifconfig ${TUN_DEV} down
ip tuntap del dev ${TUN_DEV} mode tun
echo -e "Tun device removed!"
}

function usage() {
  cat <<EOF
Usage:
  -r  Run tun2socks
  -s  Stop tun2socks
EOF
}

case "${1}" in
  -r)
    if [[ $TUN2SOCKS_MODE == "true" ]]; then
      start_tun
    else
      start_redsocks
    fi
    ;;
  -s)
    if [[ $TUN2SOCKS_MODE == "true" ]]; then
      stop_tun
    else
      stop_redsocks
    fi
    ;;
  *)
    usage
    ;;
esac
