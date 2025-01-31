#!/bin/bash

set -euxo pipefail

LOG_FILE="/var/chainnodes_install.log" # Path to the log file

# Variables
NVME_DEVICE="/dev/nvme0n1"
MOUNT_POINT="/mnt/blockchain"
FSTAB_ENTRY=""

# Function to execute a step only if it hasn't been executed
execute_step() {
    local step="$1"

    # Check if the step was already executed
    if grep -q "^${step}$" "$LOG_FILE" 2>/dev/null; then
        echo "Step '${step}' was already executed. Skipping..."
    else
        echo "Executing step '${step}'..."
        eval "$step" # Execute the provided function/command
        if [ $? -eq 0 ]; then
            echo "$step" >>"$LOG_FILE" # Mark the step as executed
            echo "Step '${step}' completed and logged."
        else
            echo "Step '${step}' failed!"
            return 1
        fi
    fi
}

# Enable Docker

step_enable_docker() {
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y $pkg; done

    # Add Docker's official GPG key:
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update

    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo systemctl enable docker
    sudo systemctl start docker
} && execute_step "step_enable_docker"

# Mount NVME

step_mount_nvme() {
    echo "Step Mount NVME"
    # Partition the NVMe device (if needed)
    parted $NVME_DEVICE --script mklabel gpt
    parted $NVME_DEVICE --script mkpart primary ext4 0% 100%

    # Format the partition
    PARTITION="${NVME_DEVICE}p1"
    echo "Formatting $PARTITION as ext4..."
    mkfs.ext4 $PARTITION

    # Create a mount point and mount the drive
    echo "Creating mount point at $MOUNT_POINT..."
    mkdir -p $MOUNT_POINT

    # Update /etc/fstab to make the mount permanent
    echo "Updating /etc/fstab..."
    UUID=$(blkid -s UUID -o value $PARTITION)
    echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 2" >>/etc/fstab

    # Mount the drive
    mount -a
} && execute_step "step_mount_nvme"

# Move Docker root to NVME

step_move_docker_root() {
    echo "Stopping Docker service..."
    systemctl stop docker

    # Create Docker data directory on the NVMe drive
    DOCKER_DATA_DIR="$MOUNT_POINT/docker"
    echo "Creating Docker data directory at $DOCKER_DATA_DIR..."
    mkdir -p $DOCKER_DATA_DIR

    # Update Docker configuration to use the new data directory
    echo "Updating Docker configuration..."
    DOCKER_CONFIG_FILE="/etc/docker/daemon.json"
    if [ -f $DOCKER_CONFIG_FILE ]; then
        cp $DOCKER_CONFIG_FILE ${DOCKER_CONFIG_FILE}.bak
    fi
    echo '{"data-root": "'$DOCKER_DATA_DIR'"}' >$DOCKER_CONFIG_FILE

    # Start Docker service
    echo "Starting Docker service..."
    systemctl start docker

    # Verify Docker root directory
    echo "Verifying Docker root directory..."
    docker info | grep "Docker Root Dir"
} && execute_step "step_move_docker_root"

# Install Dappnode Prerequesites besides Docker

step_install_dappnode_prerequesites() {
    # Install xz
    [ -f "/usr/bin/xz" ] || (apt-get install -y xz-utils)
    # Only install wireguard-dkms if needed
    if modprobe wireguard >/dev/null 2>&1; then
        echo -e "\e[32m \n\n wireguard-dkms is already installed \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        install_wireguard_dkms 2>&1 | tee -a $LOG_FILE
    fi

    # Only install lsof if needed
    if lsof -v >/dev/null 2>&1; then
        echo -e "\e[32m \n\n lsof is already installed \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        install_lsof 2>&1 | tee -a $LOG_FILE
    fi

    ## Add missing interfaces
    if [ -f /usr/src/dappnode/hotplug ]; then
        # shellcheck disable=SC2013
        for IFACE in $(grep "en.*" /usr/src/dappnode/hotplug); do
            # shellcheck disable=SC2143
            if [[ $(grep -L "$IFACE" /etc/network/interfaces) ]]; then
                {
                    echo "# $IFACE"
                    echo "allow-hotplug $IFACE"
                    echo "iface $IFACE inet dhcp"
                } >>/etc/network/interfaces
            fi
        done
    fi
} && execute_step "step_install_dappnode_prerequesites"

# Install Dappnode

step_install_dappnode() {
    wget -O - https://installer.dappnode.io | sudo bash
} && execute_step "step_install_dappnode"


step_configure_environment() {
    echo "[ -f /usr/src/dappnode/DNCORE/.dappnode_profile ] && source /usr/src/dappnode/DNCORE/.dappnode_profile" >> ~/.profile
} && execute_step "step_configure_environment"


# restart

step_restart_after_first_installation() {
    echo step_restart_after_first_installation >>"$LOG_FILE" # can't do it after actual restart
    shutdown -r now
} && execute_step "step_restart_after_first_installation"

# WIREGUARD INSTALLATION
install_wireguard_dkms() {
    apt-get update -y

    apt-get install wireguard-dkms -y | tee -a $LOG_FILE

    if modprobe wireguard >/dev/null 2>&1; then
        echo -e "\e[32m \n\n Verified wiregurd-dkms installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        echo -e "\e[31m \n\n WARNING: wireguard kernel module is not installed, Wireguard DAppNode package might not work! \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    fi
}

# LSOF INSTALLATION: used to scan host port 80 in use, https package installation will deppend on it
install_lsof() {
    apt-get update -y
    apt-get install lsof -y | tee -a $LOG_FILE
    if lsof -v >/dev/null 2>&1; then
        echo -e "\e[32m \n\n Verified lsof installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        echo -e "\e[31m \n\n WARNING: lsof not installed, HTTPS DAppNode package might not be installed! \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    fi
}

# IPTABLES INSTALLATION: mandatory for docker, on bullseye is not installed by default
install_iptables() {
    apt-get update -y
    apt-get install iptables -y | tee -a $LOG_FILE
    if iptables -v >/dev/null 2>&1; then
        echo -e "\e[32m \n\n Verified iptables installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        echo -e "\e[31m \n\n WARNING: iptables not installed, Docker may not work! \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    fi
}
