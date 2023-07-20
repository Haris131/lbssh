# lbssh
LBSSH is open source script for tunneling internet using SSH on OpenWRT with ease.

## Requirements
- bash
- curl
- screen
- jq
- Python 3
- OpenSSH
- sshpass
- badvpn-tun2socks
- redsocks
- stubby

## Working Features:
- SSH with proxy (Load-Balance)

## Installation
```sh
opkg update && opkg install bash curl screen jq python3 openssh-client sshpass corkscrew redsocks badvpn stubby
```

## How to run
- lb.sh to run or stop service
- cfg.sh to add or del config

## Credits
- [Stl](https://github.com/wegare123/stl)
- [Libernet](https://github.com/lutfailham96/libernet)
- [PumpkinLB](https://github.com/kata198/PumpkinLB)
