#!/bin/bash

set -e

DIR=/usr/share/chainnode
URL=https://raw.githubusercontent.com/chainnodesorg/chainnode-updater/refs/heads/main
LOG=/var/chainnode_install.log

mkdir -p $DIR
curl -fsSL "$URL/update.sh" -o "$DIR/update.sh"
chmod +x "$DIR/update.sh"

echo "51 0-23/10 * * * root $DIR/update.sh" > "/etc/cron.d/chainnode"
chmod 600 "/etc/cron.d/chainnode"
systemctl restart cron

export CHAINNODE_NODELAY=1
. $DIR/update.sh
