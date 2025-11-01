#!/usr/bin/env bash
set -e

DIRECTORY="/vagrant/shared/"

sudo apt-get update -y
sudo apt-get install -y slurm-wlm munge sshpass nfs-common slurmdbd mariadb-server

echo "192.168.56.10 node-app" | sudo tee -a /etc/hosts
echo "192.168.56.11 node-login" | sudo tee -a /etc/hosts
echo "192.168.56.12 node-storage" | sudo tee -a /etc/hosts
echo "192.168.56.13 node-01" | sudo tee -a /etc/hosts
echo "192.168.56.14 node-02" | sudo tee -a /etc/hosts

sudo useradd -m -s /bin/bash -u 1002 atroxgateway && echo "atroxgateway:P@ssw0rd123!" | sudo chpasswd
sudo usermod -aG sudo atroxgateway
sudo cp /etc/skel/.bashrc /home/atroxgateway/.bashrc
sudo chown atroxgateway:atroxgateway /home/atroxgateway/.bashrc

echo "atroxgateway ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/atroxgateway
echo "Defaults:atroxgateway !requiretty" | sudo tee -a /etc/sudoers.d/atroxgateway
sudo chmod 0440 /etc/sudoers.d/atroxgateway

sudo mkdir -p /etc/slurm-llnl

cat <<EOF | sudo tee /etc/slurm-llnl/slurm.conf
ClusterName=leo-atrox
ControlMachine=node-login
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
AccountingStorageHost=node-login
ProctrackType=proctrack/linuxproc
NodeName=node-01 CPUs=2 State=UNKNOWN
NodeName=node-02 CPUs=2 State=UNKNOWN
PartitionName=compute Nodes=node-01,node-02 Default=YES MaxTime=INFINITE State=UP
EOF

cat <<EOF | sudo tee /etc/slurm-llnl/slurmdbd.conf
AuthType=auth/munge
DbdHost=localhost
SlurmUser=slurm
StorageType=accounting_storage/mysql
StorageHost=localhost
StoragePort=3306
StoragePass=slurm
StorageUser=slurm
StorageLoc=slurm_acct_db
EOF

sudo chown slurm:slurm /etc/slurm-llnl/slurmdbd.conf
sudo chmod 600 /etc/slurm-llnl/slurmdbd.conf

sudo mysql -e "CREATE DATABASE IF NOT EXISTS slurm_acct_db;"
sudo mysql -e "CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY 'slurm';"
sudo mysql -e "GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"
sudo systemctl enable mariadb
sudo systemctl start mariadb

sudo mkdir -p /var/spool/slurm /var/spool/slurmd
sudo chown slurm:slurm /var/spool/slurm /var/spool/slurmd

if [ ! -f /etc/munge/munge.key ]; then
  sudo /usr/sbin/mungekey --create
fi
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key

if [[ -n "$(ls -A "$DIRECTORY")" ]]; then
  sudo rm $DIRECTORY*
fi
sudo cp /etc/munge/munge.key /home/vagrant/munge.key
sudo chown vagrant:vagrant /home/vagrant/munge.key
sudo -u vagrant cp /home/vagrant/munge.key /vagrant/shared/munge.key

sudo mkdir -p /hpc-home
echo "192.168.56.12:/home    /hpc-home   nfs auto,nofail,rsize=32768,wsize=32768 0 0" | sudo tee -a /etc/fstab
sudo mkdir -p /opt/apps
echo "192.168.56.12:/opt/apps   /opt/apps   nfs auto,nofail,rsize=32768,wsize=32768 0 0" | sudo tee -a /etc/fstab
echo "Esperando a que el servidor NFS en 'node-storage' esté listo..."
until showmount -e 192.168.56.12 | grep -q '/home'; do
  echo "Servidor NFS no está listo todavía, reintentando en 5 segundos..."
  sleep 5
done
echo "Esperando a que el export /opt/apps esté disponible..."
until showmount -e 192.168.56.12 | grep -q '/opt/apps'; do
  echo "Export /opt/apps no está listo todavía, reintentando en 5 segundos..."
  sleep 5
done
sudo mount -a

sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
if [ -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf ]; then
    sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
fi
sudo systemctl restart sshd

sudo systemctl enable munge slurmctld slurmdbd
sudo systemctl restart munge
sudo systemctl restart slurmdbd
sudo systemctl restart slurmctld
echo "Esperando a que slurmdbd inicie 5 segundos... "
sleep 5
sudo sacctmgr -i add cluster leo-atrox
sudo sacctmgr -i add account admin Description="Cuenta para administradores"
sudo sacctmgr -i add account default Description="Default user account"
sudo sacctmgr -i add user atroxgateway Account=admin AdminLevel=Administrator
#If sinfo -> slurm_load_partitions: Unable to contact slurm controller (connect failure)
#sudo mysql -e "GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';"
#sudo systemctl restart munge 
#sudo systemctl restart slurmdbd 
#sudo systemctl restart slurmctld