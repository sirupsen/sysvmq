# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure('2') do |config|
  config.vm.box = "precise"
  config.ssh.forward_agent = true

  config.vm.provider :vmware_fusion do |vmware|
    config.vm.box_url = "http://shopify-vagrant.s3.amazonaws.com/ubuntu-12.04_vmware.box"
  end

  config.vm.provision :shell, path: "provision.sh"
end
