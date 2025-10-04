#!/usr/bin/env bash
set -e

sudo apt-get update -y
sudo apt-get install -y slurm-client munge nfs-common curl nginx build-essential libpam0g-dev

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

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 18

sudo ln -sf /root/.nvm/versions/node/v18.20.8/bin/node /usr/local/bin/node
sudo ln -sf /root/.nvm/versions/node/v18.20.8/bin/npx /usr/local/bin/npx

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
}
EOF

sudo ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/default
sudo systemctl restart nginx

sudo systemctl enable munge
sudo systemctl restart munge