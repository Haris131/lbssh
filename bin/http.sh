#!/bin/bash

# HTTP Proxy Wrapper
# by Lutfa Ilham
# v1.0.0

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

LBSSH_DIR="/root/lbssh"
SERVICE_NAME="HTTP Proxy"
if [[ ${2} == "-c" ]]; then
  SSH_CONFIG="${3}"
  CC="$(echo ${SSH_CONFIG} | awk -F '.' '{print $1}')"
  CO="$(echo ${CC} | awk -F '/'  '{print NF-1}')"
  CF="$(echo ${CC} | awk -F '/' -v x=$((${CO}+1)) '{print $x}')"
else
  echo "${0} -r -c config.json" 1>&2
  echo "${0} -s -c config.json" 1>&2
  exit 1
fi
LISTEN_PORT="$(grep 'port":' ${SSH_CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '3p')"

function run() {
  echo -e "Starting ${SERVICE_NAME} service ..."
  screen -dmS http-proxy-${CF} python3 -u "${LBSSH_DIR}/bin/http.py" "${SSH_CONFIG}" -l ${LISTEN_PORT}
  echo -e "${SERVICE_NAME} service started!"
}

function stop() {
  echo -e "Stopping ${SERVICE_NAME} service ..."
  kill $(screen -list | grep http-proxy-${CF} | awk -F '[.]' {'print $1'})
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
