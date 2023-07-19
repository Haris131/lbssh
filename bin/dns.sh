#!/bin/bash

# DNS Wrapper
# by Lutfa Ilham
# v1.0.0

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

LBSSH_DIR="/root/lbssh"
SERVICE_NAME="DNS Resolver"

function run() {
  echo -e "Starting ${SERVICE_NAME} service ..."
  # initialize iptables
  iptables -w -t nat -A OUTPUT ! -d 127.0.0.1 -p udp --dport 53 -j REDIRECT --to-ports 5453
  iptables -w -t nat -A OUTPUT ! -d 127.0.0.1 -p tcp --dport 53 -j REDIRECT --to-ports 5453
  screen -AmdS stubby stubby -C "${LBSSH_DIR}/config/stubby.yml" -v 0 \
    && echo -e "${SERVICE_NAME} service started!"
}

function stop() {
  echo -e "Stopping ${SERVICE_NAME} service ..."
  # remove iptables
  iptables -w -t nat -D OUTPUT ! -d 127.0.0.1 -p udp --dport 53 -j REDIRECT --to-ports 5453
  iptables -w -t nat -D OUTPUT ! -d 127.0.0.1 -p tcp --dport 53 -j REDIRECT --to-ports 5453
  kill $(screen -list | grep stubby | awk -F '[.]' {'print $1'})
  killall stubby
  echo -e "${SERVICE_NAME} service stopped!"
}

function usage() {
  cat <<EOF
Usage:
  -r  Run ${SERVICE_NAME} service
  -s  Stop ${SERVICE_NAME} service
EOF
}

case "${1}" in
  -r)
    run
    ;;
  -s)
    stop
    ;;
  *)
    usage
    ;;
esac
