VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
    config.vm.box = "centos65"

    config.vm.provision "shell",
        inline: "yum install -y emacs"
end
