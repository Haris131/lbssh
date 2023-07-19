#!/bin/bash

# SSH Loop Wrapper
# by Lutfa Ilham
# v1.0.0

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

function connect() {
  sshpass -p "${2}" ssh \
    -4CND "${5}" \
    -p "${4}" \
    -o TCPKeepAlive=yes \
    -o ServerAliveInterval=180 \
    -o ServerAliveCountMax=2 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${1}@${3}"
}

function connect_with_proxy() {
  sshpass -p "${2}" ssh \
    -4CND "${5}" \
    -p "${4}" \
    -o TCPKeepAlive=yes \
    -o ServerAliveInterval=180 \
    -o ServerAliveCountMax=2 \
    -o ProxyCommand="/usr/bin/corkscrew ${6} ${7} %h %p" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${1}@${3}"
}

function connect_slowdns() {
  sshpass -p "${2}" ssh \
    -N -D "${4}" \
    -o TCPKeepAlive=yes \
    -o ServerAliveInterval=180 \
    -o ServerAliveCountMax=2 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o HostKeyAlias="${3}" \
    -p 2222 \
    "${1}"@127.0.0.1
}

case "${1}" in
  -d)
    while true; do
      # command username password host port dynamic_port
      connect "${2}" "${3}" "${4}" "${5}" "${6}"
      sleep 3
    done
    ;;
  -e)
    while true; do
      # command username password host port dynamic_port proxy_ip proxy_port
      connect_with_proxy "${2}" "${3}" "${4}" "${5}" "${6}" "${7}" "${8}"
      sleep 3
    done
    ;;
  -s)
    while true; do
      # command username password host dynamic_port
      connect_slowdns "${2}" "${3}" "${4}" "${5}"
      sleep 3
    done
    ;;
esac
