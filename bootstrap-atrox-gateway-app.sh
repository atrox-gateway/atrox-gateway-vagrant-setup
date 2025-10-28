#!/usr/bin/env bash
set -e

# Script de bootstrap para la VM "app" del Atrox Gateway
# Este script instala y configura los servicios necesarios
# para el entorno de desarrollo del Atrox Gateway.

# Variables
REPO_PATH="/opt/atrox-gateway"
SHARED_PATH="/vagrant/shared"

sudo apt update -y
sudo apt install -y git nginx redis-server slurm-client munge nfs-common curl sshpass build-essential libpam0g-dev sshpass

echo "192.168.56.2 hpc-master" | sudo tee -a /etc/hosts
echo "192.168.56.3 app" | sudo tee -a /etc/hosts

sudo useradd -m -s /bin/bash -u 1002 atroxgateway && echo "atroxgateway:P@ssw0rd123!" | sudo chpasswd
sudo usermod -aG sudo atroxgateway
sudo cp /etc/skel/.bashrc /home/atroxgateway/.bashrc
cat <<EOF | sudo tee -a /home/atroxgateway/.bash_profile
echo ""
echo "***********************************************************"
echo "Bienvenido, \$USER. Tus archivos del HPC están en /hpc_home"
echo "Usa el comando 'hpc' para ir directamente allí."
echo "***********************************************************"
echo ""
alias hpc='cd /hpc_home/\$USER'
EOF
sudo chown -R atroxgateway:atroxgateway /home/atroxgateway/

sudo -u atroxgateway ssh-keygen -t rsa -b 2048 -N "" -f /home/atroxgateway/.ssh/id_rsa <<< y || true 
sudo -u atroxgateway sshpass -p 'P@ssw0rd123!' ssh-copy-id -o StrictHostKeyChecking=no atroxgateway@hpc-master

# 3. Creación de Usuarios de Servicio de Linux (para min. privilegio)
#sudo useradd -r -s /sbin/nologin gateway-manager
#sudo useradd -r -s /sbin/nologin mgmt-service
sudo usermod -aG www-data atroxgateway

git clone https://github.com/atrox-gateway/atrox-gateway-app.git "$REPO_PATH"

#sudo chown -R gateway-manager:gateway-manager "$REPO_PATH"/packages/backend/atrox-services
#sudo chown -R mgmt-service:mgmt-service "$REPO_PATH"/packages/backend/atrox-admin-services
#sudo chown -R gateway-manager:gateway-manager "$REPO_PATH"/scripts/
#sudo chmod -R o+rX "$REPO_PATH"/packages/backend/atrox-user-pun""

sudo mkdir -p /var/run/atrox-puns
sudo chown atroxgateway:www-data /var/run/atrox-puns
sudo chmod 770 /var/run/atrox-puns

sudo rm -f /etc/nginx/sites-enabled/default

# Ensure common nginx directories and include files exist so `nginx -t` doesn't fail
sudo mkdir -p /etc/nginx/puns-enabled /etc/nginx/sites-enabled /etc/nginx/conf.d
if [ ! -f /etc/nginx/user_map.conf ]; then
    sudo install -m 644 /dev/null /etc/nginx/user_map.conf
    echo "# user_map.conf - generated placeholder" | sudo tee /etc/nginx/user_map.conf > /dev/null
fi
sudo chown atroxgateway:www-data /etc/nginx/user_map.conf

# Ensure a public directory exists for the frontend root referenced in the config
sudo mkdir -p /var/www/atrox-ui
sudo chown -R www-data:www-data /var/www/atrox-ui || true
sudo bash -c 'echo "<html><body><h1>Atrox Gateway - Frontend OK</h1></body></html>" > /var/www/atrox-ui/index.html'

# Also enable the app.conf site so the default_server in it is active (safe - it will be symlinked)
#sudo ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/app.conf

sudo nginx -t && sudo systemctl restart nginx
sudo systemctl enable redis-server
sudo systemctl start redis-server

# Configurar Slurm para usar el nodo maestro como el único nodo de cómputo
sudo mkdir -p /etc/slurm-llnl
cat <<EOF | sudo tee /etc/slurm-llnl/slurm.conf
ClusterName=hpc-master
ControlMachine=hpc-master
SlurmUser=slurm
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge
StateSaveLocation=/var/spool/slurm
SlurmdSpoolDir=/var/spool/slurmd
SwitchType=switch/none
MpiDefault=none
SlurmctldDebug=info
SlurmdDebug=info
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=hpc-master
ProctrackType=proctrack/linuxproc
NodeName=hpc-master CPUs=1 State=UNKNOWN
PartitionName=MasterNode Nodes=hpc-master Default=YES MaxTime=INFINITE State=UP
EOF
sudo mkdir -p /var/spool/slurm /var/spool/slurmd
sudo chown slurm:slurm /var/spool/slurm /var/spool/slurmd

if [ -f /shared/munge.key ]; then
  sudo mkdir -p /etc/munge
  sudo cp /vagrant/shared/munge.key /etc/munge/munge.key
  sudo chown munge:munge /etc/munge/munge.key
  sudo chmod 400 /etc/munge/munge.key
else
  echo "ERROR: /shared/munge.key no encontrado"
  exit 1
fi

sudo mkdir -p /hpc_home
echo "192.168.56.2:/home    /hpc_home   nfs auto,nofail,rsize=32768,wsize=32768 0 0" | sudo tee -a /etc/fstab
echo "Esperando a que el servidor NFS en 'hpc-master' esté listo..."
until showmount -e 192.168.56.2 | grep -q '/home'; do
  echo "Servidor NFS no está listo todavía, reintentando en 5 segundos..."
  sleep 5
done
sudo mount -a

sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
if [ -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf ]; then
    sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
fi
sudo systemctl restart sshd

sudo mkdir -p /etc/nginx/puns-enabled
sudo touch /etc/nginx/user_map.conf
sudo rm -f /etc/nginx/sites-enabled/default

sudo tee /etc/nginx/nginx.conf > /dev/null <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    gzip on;

    map $cookie_user_session $user_backend {
        default "";
        include /etc/nginx/user_map.conf;
    }

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
    include /etc/nginx/puns-enabled/*.conf;
}
EOF

sudo tee /etc/nginx/sites-available/app.conf > /dev/null <<'EOF'
server {
    listen 80 default_server;
    server_name _;

    location /login {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
    }

    location /api/ {
        if ($user_backend = "") {
            return 401 'No Autorizado';
        }
        proxy_pass http://$user_backend;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
    }

    location / {
        root /var/www/atrox-ui;
        index index.html index.htm;
        try_files $uri $uri/ /index.html;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/default
sudo systemctl restart nginx

sudo systemctl enable munge
sudo systemctl restart munge

sudo chmod a+x "$REPO_PATH"/install.sh
. "$REPO_PATH"/install.sh