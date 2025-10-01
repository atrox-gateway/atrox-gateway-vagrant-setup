#!/usr/bin/env bash
set -e

sudo apt-get update -y
sudo apt-get install -y slurm-client munge nfs-common

echo "192.168.56.2 hpc-master" | sudo tee -a /etc/hosts
echo "192.168.56.3 app" | sudo tee -a /etc/hosts

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

if [ -f /shared/munge.key ]; then
  sudo mkdir -p /etc/munge
  sudo cp /vagrant/shared/munge.key /etc/munge/munge.key
  sudo chown munge:munge /etc/munge/munge.key
  sudo chmod 400 /etc/munge/munge.key
else
  echo "ERROR: /shared/munge.key no encontrado"
  exit 1
fi

sudo systemctl enable munge
sudo systemctl restart munge

cat <<EOF | sudo tee ~/nfs_setup.sh
sudo mkdir -p /home
echo "192.168.56.2:/home /home nfs auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0" | sudo tee -a /etc/fstab
sudo mount -a
EOF
chmod a+x ~/nfs_setup.sh


