# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box = "geerlingguy/ubuntu2004"
  config.vm.synced_folder '.', '/vagrant', disabled: true
  config.ssh.insert_key = false

  config.vm.provider "virtualbox" do |v|
    v.name = "laptop-personal-ubuntu-test"
    v.memory = 1024
    v.cpus = 2
  end

  config.vm.hostname = "laptop-test"
  config.vm.network :private_network, ip: "192.168.56.7"

  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "main.yml"
    ansible.become = true
  end

end
