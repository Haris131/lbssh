#!/bin/bash

# SSH Connector Wrapper
# by Lutfa Ilham
# v1.0.0

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

LBSSH_DIR="/root/lbssh"
SERVICE_NAME="SSH"
if [[ ${2} == "-c" ]]; then
  SSH_CONFIG="${3}"
  CC="$(echo ${SSH_CONFIG} | awk -F '.' '{print $1}')"
  CO="$(echo ${CC} | awk -F '/'  '{print NF-1}')"
  CF="$(echo ${CC} | awk -F '/' -v x=$((${CO}+1)) '{print $x}')"
  DYNAMIC_PORT="${4}"
else
  echo "${0} -r -c config.json" 1>&2
  echo "${0} -s -c config.json" 1>&2
  exit 1
fi
SSH_HOST="$(grep 'host":' ${SSH_CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g')"
SSH_PORT="$(grep 'port":' ${SSH_CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '1p')"
SSH_USER="$(grep 'username":' ${SSH_CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g')"
SSH_PASS="$(grep 'password":' ${SSH_CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g')"
PROXY_IP="$(grep 'ip":' ${SSH_CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '2p')"
PROXY_PORT="$(grep 'port":' ${SSH_CONFIG} | awk '{print $2}' | sed 's/,//g; s/"//g' | sed -n '2p')"

function run() {
  mkdir -p ${LBSSH_DIR}/log/${CF}
  cd ${LBSSH_DIR}/log/${CF}
  echo "" > screenlog.0
  "${LBSSH_DIR}/bin/http.sh" -r -c ${SSH_CONFIG}
  echo -e "Starting ${SERVICE_NAME} service ..."
  screen -L -AmdS ssh-connector-${CF} "${LBSSH_DIR}/bin/ssh-loop.sh" -e "${SSH_USER}" "${SSH_PASS}" "${SSH_HOST}" "${SSH_PORT}" "${DYNAMIC_PORT}" "${PROXY_IP}" "${PROXY_PORT}"
  echo -e "${SERVICE_NAME} service started!"
}

function stop() {
  echo "" > "${LBSSH_DIR}/log/${CF}/screenlog.0"
  echo -e "Stopping ${SERVICE_NAME} service ..."
  kill $(screen -list | grep ssh-connector-${CF} | awk -F '[.]' {'print $1'})
  echo -e "${SERVICE_NAME} service stopped!"
  "${LBSSH_DIR}/bin/http.sh" -s -c ${SSH_CONFIG}
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
