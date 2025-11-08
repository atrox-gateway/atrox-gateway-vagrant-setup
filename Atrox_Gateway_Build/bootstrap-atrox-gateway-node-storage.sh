#!/usr/bin/env bash
set -e

sudo apt-get update -y
sudo apt-get install -y nfs-kernel-server

echo "Configurando /etc/hosts..."
echo "192.168.56.10 app" | sudo tee -a /etc/hosts
echo "192.168.56.11 node-login" | sudo tee -a /etc/hosts
echo "192.168.56.12 node-storage" | sudo tee -a /etc/hosts
echo "192.168.56.13 node-01" | sudo tee -a /etc/hosts
echo "192.168.56.14 node-02" | sudo tee -a /etc/hosts

if [ -z "${ATROX_PASSWORD:-}" ]; then
    echo "ERROR: ATROX_PASSWORD is not set. Export it on the host before running vagrant up. Example: export ATROX_PASSWORD='your-password'" >&2
    exit 1
fi
sudo useradd -m -s /bin/bash -u 1002 atroxgateway && echo "atroxgateway:${ATROX_PASSWORD}" | sudo chpasswd
sudo usermod -aG sudo atroxgateway

echo "atroxgateway ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/atroxgateway
echo "Defaults:atroxgateway !requiretty" | sudo tee -a /etc/sudoers.d/atroxgateway
sudo chmod 0440 /etc/sudoers.d/atroxgateway

echo "/home    192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports
sudo mkdir -p /opt/apps
sudo chown atroxgateway:atroxgateway /opt/apps || true
echo "/opt/apps 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -a
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server

sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
if [ -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf ]; then
    sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
fi
sudo systemctl restart sshd