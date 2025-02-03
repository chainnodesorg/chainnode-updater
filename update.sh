#!/bin/bash

set -e
[ -z "$CHAINNODE_NODELAY" ] && sleep $((RANDOM % 1200))

DIR=/usr/share/chainnode
URL=https://raw.githubusercontent.com/chainnodesorg/chainnode-updater/refs/heads/main
LOG=/var/chainnode_install.log

get_last_startup_time() {
    stat -c %Y "$DIR/startup.sh" 2>/dev/null || echo 0
}

PREV=$(get_last_startup_time)
curl -z "$DIR/startup.sh" -o "$DIR/startup.sh" "$URL/startup.sh" 
NEW=$(get_last_startup_time)

if [ "$PREV" -ne "$NEW" ]; then
    echo "$(date) - New version detected. Updating script..." | tee -a "$LOG"
    curl -fsSL "$URL/startup.sh" -o "$DIR/startup.sh"
    chmod +x "$DIR/startup.sh"
    echo "$(date) - Update completed successfully." | tee -a "$LOG"
    exec "$DIR/startup.sh"
else
    echo "$(date) - No updates found." | tee -a "$LOG"
fi

