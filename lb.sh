#!/bin/bash
clear

LBSSH_DIR="/root/lbssh"
CONFIG="${LBSSH_DIR}/config/config.json"
CONFIG_LB="$(grep SSH ${CONFIG} | awk '{print $1}' | sed 's/://g; s/"//g')"

function start_lb {
for CFG in ${CONFIG_LB}; do
  CFG_FILE="$(cat ${CONFIG} | jq .$CFG.config | awk '{print $1}' | sed 's/://g; s/"//g')"
  CC="$(echo ${SSH_CONFIG} | awk -F '.' '{print $1}')"
  CO="$(echo ${CC} | awk -F '/'  '{print NF-1}')"
  CF="$(echo ${CC} | awk -F '/' -v x=$((${CO}+1)) '{print $x}')"
  SOCKS_PORT="$(cat ${CONFIG} | jq .$CFG.socks.port | awk '{print $1}' | sed 's/://g; s/"//g')"
  echo -e "###### ${CFG} ######"
  ${LBSSH_DIR}/bin/ssh.sh -r -c ${CFG_FILE} ${SOCKS_PORT}
  counter=0
  max_retries=3
  while [[ "${counter}" -lt "${max_retries}" ]]; do
    sleep 5
    mkdir -p ${LBSSH_DIR}/log/${CF}
    if [ ! -f $(grep Permission ${LBSSH_DIR}/log/${CF}/screenlog.0 2>/dev/null|awk "NR==1"|awk '{print $4}') ]; then
      echo -e "Username/Password Salah/Kadaluarsa."
      break
    fi
    echo -e "Checking connection, attempt: $[${counter} + 1]"
    if curl -so /dev/null -x "socks5://127.0.0.1:${SOCKS_PORT}" "http://bing.com"; then
      echo -e "Socks connection available!"
      break
    fi
    counter=$[${counter} + 1]
    # max retries reach
    if [[ "${counter}" -eq "${max_retries}" ]]; then
      echo -e "Socks connection unavailable!"
      ${LBSSH_DIR}/bin/ssh.sh -s -c ${CFG_FILE}
      break
    fi
  done
done
echo -e "###### AUTO RECONNECT ######"
${LBSSH_DIR}/bin/recon.sh -r
echo -e "###### LOAD BALANCE ######"
screen -dmS load-balance python3 -u ${LBSSH_DIR}/bin/loadbalancer.py ${LBSSH_DIR}/config/config.cfg
sleep 2
echo -e "###### TUN2SOCKS ######"
${LBSSH_DIR}/bin/tun2socks.sh -r tun
echo -e "###### DNS Resolver ######"
${LBSSH_DIR}/bin/dns.sh -r
}

function stop_lb {
${LBSSH_DIR}/bin/dns.sh -s
${LBSSH_DIR}/bin/tun2socks.sh -s tun
kill $(screen -list | grep load-balance | awk -F '[.]' {'print $1'})
${LBSSH_DIR}/bin/recon.sh -s
for CFG in ${CONFIG_LB}; do
  CFG_FILE="$(cat ${CONFIG} | jq .$CFG.config | awk '{print $1}' | sed 's/://g; s/"//g')"
  ${LBSSH_DIR}/bin/ssh.sh -s -c ${CFG_FILE}
done
}

function usage() {
  cat <<EOF
Usage:
  -r  Run service
  -s  Stop service
EOF
}

case $1 in
  -r)
  start_lb
  ;;
  -s)
  stop_lb
  ;;
  *)
  usage
  ;;
esac
