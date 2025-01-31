#!/bin/bash

DIR=/usr/share/chainnode
URL=https://raw.githubusercontent.com/chainnodesorg/chainnode-updater/refs/heads/main
LOG=/var/chainnode_install.log

get_remote_mod_time() {
    curl -sI "$URL/startup.sh" | grep -i "Last-Modified" | cut -d' ' -f2- | tr -d '\r' 
}
get_local_mod_time() {
     stat -c %Y "$DIR/startup.sh" 2>/dev/null || echo 0 
}

REMOTE_TIME=$(date -d "$(get_remote_mod_time)" +%s 2>/dev/null || echo 0)
LOCAL_TIME=$(get_local_mod_time)

if [ "$REMOTE_TIME" -gt "$LOCAL_TIME" ]; then
    echo "$(date) - New version detected. Updating script..." | tee -a "$LOG"
    curl -fsSL "$URL" -o "$DIR/startup.sh"
    chmod +x "$DIR/startup.sh"
    echo "$(date) - Update completed successfully." | tee -a "$LOG"
    exec "$DIR/startup.sh"
else
    echo "$(date) - No updates found." | tee -a "$LOG"
fi

