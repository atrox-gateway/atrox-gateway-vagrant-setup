Vagrant.configure("2") do |config|
  config.vm.synced_folder "./shared", "/shared", type: "rsync", rsync__auto: true
  
  config.vm.define "master" do |master|
    master.vm.box = "atrox-gateway/hpc-master"
    master.vm.box_version = "1.1.0"
    master.vm.hostname = "hpc-master"
    master.vm.network "private_network", ip: "192.168.56.2"
    master.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
      vb.cpus = 8
    end
    master.ssh.insert_key = false
    master.ssh.username = ENV['VM_USERNAME']
    master.ssh.password = ENV['VM_PASSWORD']
  end
  
  config.vm.box = "ubuntu/focal64"
  config.vm.define "app" do |app|
    app.vm.hostname = "app"
    app.vm.network "private_network", ip: "192.168.56.3"
    app.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
      vb.cpus = 8
    end
    app.vm.provision "shell", path: "bootstrap-atrox-gateway-app.sh"
  end
end

