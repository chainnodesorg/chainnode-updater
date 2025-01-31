#!/bin/bash

set -e

DIR=/usr/share/chainnode
URL=https://raw.githubusercontent.com/chainnodesorg/chainnode-updater/refs/heads/main
LOG=/var/chainnode_install.log

mkir -p $DIR
curl -fsSL "$URL/update.sh" -o "$DIR/update.sh"
chmod +x "$DIR/update.sh"

echo "* */10 * * * root /usr/local/bin/updater.sh" > "/etc/cron.d/chainnode"
chmod 600 "/etc/cron.d/chainnode"
systemctl restart cron


. $DIR/update.sh

