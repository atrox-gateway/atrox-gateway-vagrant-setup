#!/usr/bin/env sh

sudo sh -c '> /etc/nginx/user_map.conf'
sudo systemctl restart nginx

sudo mkdir -p /home/atroxgateway/.ssh
sudo chown atroxgateway:atroxgateway /home/atroxgateway/.ssh
sudo chmod 700 /home/atroxgateway/.ssh
if [ ! -f /home/atroxgateway/.ssh/id_rsa ]; then
	sudo -u atroxgateway ssh-keygen -t rsa -b 2048 -N "" -f /home/atroxgateway/.ssh/id_rsa >/dev/null 2>&1 || true
fi

# Propagar la clave a los nodos (requiere ATROX_PASSWORD env var or root access to copy)
if [ -z "${ATROX_PASSWORD:-}" ]; then
	echo "ERROR: ATROX_PASSWORD is not set. Set it on the host before running provisioning: export ATROX_PASSWORD='your-password'" >&2
	exit 1
fi
sudo -u atroxgateway sshpass -p "${ATROX_PASSWORD}" ssh-copy-id -o StrictHostKeyChecking=no atroxgateway@node-login
sudo -u atroxgateway sshpass -p "${ATROX_PASSWORD}" ssh-copy-id -o StrictHostKeyChecking=no atroxgateway@node-storage
sudo -u atroxgateway sshpass -p "${ATROX_PASSWORD}" ssh-copy-id -o StrictHostKeyChecking=no atroxgateway@node-01
sudo -u atroxgateway sshpass -p "${ATROX_PASSWORD}" ssh-copy-id -o StrictHostKeyChecking=no atroxgateway@node-02

/opt/atrox-gateway/install.sh