#!/usr/bin/env bash
set -e

DIRECTORY="/vagrant/shared/"

sudo apt-get update -y
sudo apt-get install -y slurm-wlm munge sshpass nfs-kernel-server

echo "192.168.56.2 hpc-master" | sudo tee -a /etc/hosts
echo "192.168.56.3 app" | sudo tee -a /etc/hosts

sudo useradd -m -s /bin/bash -u 1010 atroxgateway && echo "atroxgateway:P@ssw0rd123!" | sudo chpasswd
sudo usermod -aG sudo atroxgateway
sudo cp /etc/skel/.bashrc /home/atroxgateway/.bashrc
sudo chown atroxgateway:atroxgateway /home/atroxgateway/.bashrc

sudo mkdir -p /etc/slurm
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
ProctrackType=proctrack/linuxproc
NodeName=hpc-master CPUs=1 State=UNKNOWN
PartitionName=MasterNode Nodes=hpc-master Default=YES MaxTime=INFINITE State=UP
EOF
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

echo "/home    192.168.56.3(rw,async,no_subtree_check)" | sudo tee /etc/exports
sudo exportfs -a
sudo systemctl restart nfs-kernel-server

sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
if [ -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf ]; then
    sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
fi
sudo systemctl restart sshd

sudo systemctl enable munge slurmctld slurmd
sudo systemctl restart munge
sudo systemctl restart slurmctld
sudo systemctl restart slurmd
