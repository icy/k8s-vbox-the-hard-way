#!/usr/bin/env ruby

# Purpose : A Vagrant file to boot up k8s nodes
# Author  : Ky-Anh Huynh
# License : MIT

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/xenial64"

  config.vm.box_check_update = false

  # path/to/master-122/Vagrantfile --> sshport 100122
  v_basepath = File.basename(File.dirname(__FILE__))
  v_role, v_index = v_basepath.split("-")
  ssh_port = "#{ENV['SSH_PORT_PREFIX'] || "10"}#{v_index}"
  internal_ip = "#{ENV['IP_PREFIX'] || "10.11.12"}.#{v_index}"

  f_hostname = File.join(File.dirname(__FILE__), "hostname")
  if File.exist?(f_hostname)
    hostname = File.open(f_hostname).readlines.first.strip
  else
    hostname = v_basepath
  end

  # https://stackoverflow.com/a/20431791
  config.vm.hostname = "#{hostname}.internal"
  config.vm.define "#{hostname}"

  puts "SSH port: #{ssh_port}, Internal IP: #{internal_ip} <-- #{hostname}"
  config.vm.network "forwarded_port", guest: 22, host: ssh_port, id: "ssh"
  config.vm.network "private_network", ip: internal_ip, virtualbox__intnet: (ENV["VBOX_PRIVATE_NETWORK_NAME"] || "testing")
  if v_role == "lb"
    config.vm.network "forwarded_port", guest: 6443, host: 6443
    # haproxy stats
    config.vm.network "forwarded_port", guest: 1936, host: 1936
  end

  config.vm.provider :virtualbox do |vb|
    vb.gui = false
    vb.memory = case v_role
    when "controller" then (ENV["MEM_CONTROLLER"] || "1024")
    when "worker" then (ENV["MEM_WORKER"] || "1024")
    when "lb" then (ENV["MEM_LB"] || "1024")
    end
    vb.name = "#{hostname}"
  end

  config.ssh.insert_key       = false
  config.ssh.private_key_path =  ["~/.vagrant.d/insecure_private_key", "~/.ssh/id_rsa"]

  f_script = File.join(File.dirname(__FILE__), "provision.sh")
  if File.exists?(f_script)
    f_contents = File.open(f_script).readlines.join()
  else
    f_contents = ""
  end
  config.vm.provision :shell, inline: <<-SHELL
    set -x

    # Using the load balancer as dns server
    if [[ -n "#{ENV['IP_LB']}" ]]; then
      echo "nameserver #{ENV['IP_LB']}" > /etc/resolvconf/resolv.conf.d/head
    fi

    wget -O /usr/bin/pacman https://github.com/icy/pacapt/raw/ng/pacapt
    chmod 755 /usr/bin/pacman
    pacman -Sy

    systemctl restart networking

    #{f_contents}
  SHELL
end
