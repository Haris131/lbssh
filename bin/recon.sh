#!/bin/bash

LBSSH_DIR="/root/lbssh"
CONFIG="${LBSSH_DIR}/config/config.json"
CONFIG_LB="$(grep SSH ${CONFIG} | awk '{print $1}' | sed 's/://g; s/"//g')"

function recon {
while true; do
  for CFG in ${CONFIG_LB}; do
    CFG_FILE="$(cat ${CONFIG} | jq .$CFG.config | awk '{print $1}' | sed 's/://g; s/"//g')"
    CC="$(echo ${SSH_CONFIG} | awk -F '.' '{print $1}')"
    CO="$(echo ${CC} | awk -F '/'  '{print NF-1}')"
    CF="$(echo ${CC} | awk -F '/' -v x=$((${CO}+1)) '{print $x}')"
    SOCKS_PORT="$(cat ${CONFIG} | jq .$CFG.socks.port | awk '{print $1}' | sed 's/://g; s/"//g')"
    echo -e "###### ${CFG} ######"
    counter=0
    max_retries=3
    while [[ "${counter}" -lt "${max_retries}" ]]; do
      sleep 5
      mkdir -p ${LBSSH_DIR}/log/${CF}
      if [ ! -f $(grep Permission ${LBSSH_DIR}/log/${CF}/screenlog.0 2>/dev/null|awk "NR==1"|awk '{print $4}') ]; then
        echo -e "Username/Password Salah/Kadaluarsa."
        ${LBSSH_DIR}/bin/ssh.sh -s -c ${CFG_FILE}
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
        sleep 2
        ${LBSSH_DIR}/bin/ssh.sh -r -c ${CFG_FILE} ${SOCKS_PORT}
        sleep 2
      fi
    done
  done
  if [ -f $(screen -list | grep load-balance | awk -F '[.]' {'print $1'}) ]; then
    screen -dmS load-balance python3 -u ${LBSSH_DIR}/bin/loadbalancer.py ${LBSSH_DIR}/config/config.cfg
  fi
  if [ -f $(screen -list | grep badvpn-tun2socks | awk -F '[.]' {'print $1'}) ]; then
    ${LBSSH_DIR}/bin/tun2socks.sh -s
    sleep 1
    ${LBSSH_DIR}/bin/tun2socks.sh -r
  fi
  sleep 300
done
}

function start_recon {
screen -dmS recon ${LBSSH_DIR}/bin/recon.sh -l
}

function stop_recon {
kill $(screen -list | grep recon | awk -F '[.]' {'print $1'})
}

case $1 in
  -r)
  start_recon
  ;;
  -s)
  stop_recon
  ;;
  -l)
  recon
  ;;
esac
