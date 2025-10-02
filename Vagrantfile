Vagrant.configure("2") do |config|
  config.vm.synced_folder "./shared", "/shared", type: "rsync", rsync__auto: true
  
  config.vm.box = "ubuntu/focal64"
  config.vm.define "atrox-gateway-hpc-master" do |master|
    master.vm.hostname = "hpc-master"
    master.vm.network "private_network", ip: "192.168.56.2"
    master.vm.provider "virtualbox" do |vb|
      vb.memory = 2048
      vb.cpus = 4
    end
    master.vm.provision "shell", path: "bootstrap.atrox-gateway-hpc-master.sh"
    master.ssh.insert_key = false
    master.ssh.username = "vagrant"
    master.ssh.password = ENV['VM_PASSWORD']
  end
  
  config.vm.box = "ubuntu/focal64"
  config.vm.define "atrox-gateway-app" do |app|
    app.vm.hostname = "app"
    app.vm.network "private_network", ip: "192.168.56.3"
    app.vm.provider "virtualbox" do |vb|
      vb.memory = 2048
      vb.cpus = 4
    end
    app.vm.provision "shell", path: "bootstrap-atrox-gateway-app.sh"
    app.ssh.insert_key = false
    app.ssh.username = "vagrant"
    app.ssh.password = ENV['VM_PASSWORD']
  end
end

