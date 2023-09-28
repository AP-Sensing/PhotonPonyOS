# Documentation is not really existent. The easies is to take a look at the tests found here: https://github.com/pykickstart/pykickstart/blob/master/tests/ 
# Misc: https://wiki.centos.org/TipsAndTricks/KickStart

# Use graphical install
graphical

%post --erroronfail --log=/root/my-post-log
cp /etc/skel/.bash* /root

# Allow adding users to the dialout group later on
# Ref: https://docs.fedoraproject.org/en-US/fedora-silverblue/troubleshooting/#_unable_to_add_user_to_group
grep -E '^dialout:' /usr/lib/group >> /etc/group
%end

# Not supported with rpm-ostree
# %packages
# @core
# %end

# Keyboard layouts
keyboard --vckeymap=de --xlayouts='de'

# System language
lang en_US.UTF-8

# Firewall configuration
firewall --enabled --ssh --port=80:tcp,443:tcp

# OSTree setup
ostreesetup --osname="ppos" --remote="ppos-compose" --url="file:///ostree/repo" --ref="fedora/38/x86_64/photon-pony" --nogpg

# Disable the Setup Agent on first boot
firstboot --disable

# Ask for network configuration
network  --bootproto=static --device=eno2 --gateway=10.0.0.1 --ip=10.0.0.62 --nameserver=10.0.0.1 --netmask=255.255.255.0 --ipv6=auto --no-activate
network  --hostname=n62-ppos

# Partition clearing information
ignoredisk --only-use=nvme0n1
clearpart --none --initlabel
# Disk partitioning information
part /boot/efi --fstype="efi" --ondisk=nvme0n1 --size=600 --fsoptions="umask=0077,shortname=winnt"
part /boot --fstype="ext4" --ondisk=nvme0n1 --size=1024
part btrfs.165 --fstype="btrfs" --ondisk=nvme0n1 --size=1906104
btrfs none --label=photonponyos_fedora --data=single btrfs.165
btrfs /opt --subvol --name=opt LABEL=photonponyos_fedora
btrfs /home --subvol --name=home LABEL=photonponyos_fedora
btrfs /usr/local --subvol --name=usr_local LABEL=photonponyos_fedora
btrfs / --subvol --name=root LABEL=photonponyos_fedora
btrfs /var/lib/aps/dts --subvol --name=var_lib_aps_dts LABEL=photonponyos_fedora
btrfs /opt/webcache --subvol --name=opt_webcache LABEL=photonponyos_fedora

# System timezone
timezone Etc/UCT --utc

#Root password
rootpw --lock
user --groups=wheel --name=dts_admin --password=$y$j9T$8nlLGisEdGIKHytfpkv0pB90$YBch7wZNtEkG57IIv/nhzUqgodILbiYbMFtySk26ay1 --iscrypted --gecos="dts_admin"

# Make sure SELinux is enabled
selinux --enforcing
