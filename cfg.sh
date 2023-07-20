#!/bin/bash
clear

LBSSH_DIR="/root/lbssh"
CONFIG="${LBSSH_DIR}/config/config.json"

# Menghitung berapa banyak entri SSH_ sudah ada dalam file JSON
ssh_count=$(jq 'keys | length' "${CONFIG}")
count=$(($ssh_count - 1))
cfg_save="/root/lbssh/config/cfg${ssh_count}.json"

function add_cfg {
# Menambahkan entri baru untuk SSH_X (gantilah X dengan angka yang diinginkan)
ssh_entry="SSH_$ssh_count"
new_entry="{ \"config\": \"${cfg_save}\", \"socks\": { \"ip\": \"127.0.0.1\", \"port\": 108$count } }"

read -p "SSH Host: " ssh_host
ssh_ip=$(ping $ssh_host -w1 -c1 | awk "NR==1" | awk -F '(' '{print $2}' | awk -F ')' '{print $1}')
read -p "SSH Port: " ssh_port
read -p "SSH Username: " ssh_username
read -p "SSH Password: " ssh_password
read -p "Payload: " payload
read -p "Proxy: " proxy
read -p "Port: " port

# Menambahkan entri SSH_X ke file JSON
jq --argjson entry "$new_entry" '. + { "'$ssh_entry'": $entry }' "${CONFIG}" > temp.json && mv temp.json "${CONFIG}"

echo '{
    "ip": "'$ssh_ip'",
    "host": "'$ssh_host'",
    "port": '$ssh_port',
    "username": "'$ssh_username'",
    "password": "'$ssh_password'",
    "http": {
        "buffer": 32768,
        "ip": "127.0.0.1",
        "port": 987'$count',
        "info": "HTTP Proxy",
        "payload": "'$payload'",
        "proxy": {
            "ip": "'$proxy'",
            "port": '$port'
        }
    }
}' > $cfg_save

CONFIG="${LBSSH_DIR}/config/config.json"
CONFIG_LB="$(grep SSH ${CONFIG} | awk '{print $1}' | sed 's/://g; s/"//g')"
CFG_ARR=()
for CFG in ${CONFIG_LB}; do
  SOCKS_IP="$(cat ${CONFIG} | jq .$CFG.socks.ip | awk '{print $1}' | sed 's/://g; s/"//g')"
  SOCKS_PORT="$(cat ${CONFIG} | jq .$CFG.socks.port | awk '{print $1}' | sed 's/://g; s/"//g')"
  CFG_ARR+=("${SOCKS_IP}:${SOCKS_PORT}")
done

CFG_LB=$(echo ${CFG_ARR[@]} | tr ' ' ',')
echo $CFG_LB
sed -i "s|5555=.*|5555=${CFG_LB}|g" ${LBSSH_DIR}/config/config.cfg

echo "Entri $ssh_entry telah ditambahkan ke dalam file ${CONFIG}."
}

function del_cfg {
echo "ada $count config ssh"
if [ $count == "0" ]; then
  exit
fi
read -p "hapus ssh nomor: " dssh
[ -z $dssh ] && dssh=$count
rm -rf /root/lbssh/config/cfg${dssh}.json
SOCKS_IP="$(cat ${CONFIG} | jq .SSH_$dssh.socks.ip | awk '{print $1}' | sed 's/://g; s/"//g')"
SOCKS_PORT="$(cat ${CONFIG} | jq .SSH_$dssh.socks.port | awk '{print $1}' | sed 's/://g; s/"//g')"
SOCKS="${SOCKS_IP}:${SOCKS_PORT}"
sed -i "s|,${SOCKS}||g" ${LBSSH_DIR}/config/config.cfg
jq 'del(.SSH_'$dssh')' ${CONFIG} > temp.json && mv temp.json "${CONFIG}"
echo "Entri SSH_$dssh telah dihapus dari file ${CONFIG}."
}

case $1 in
  add)
  add_cfg
  ;;
  del)
  del_cfg
  ;;
  *)
  echo "$0 add (to add config)"
  echo "$0 del (to del config)"
  ;;
esac
