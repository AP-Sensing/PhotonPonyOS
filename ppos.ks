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
# network --device=eth0 --bootproto=query

# Partition clearing information
ignoredisk --only-use=vda
clearpart --none --initlabel
part /boot/efi --fstype="efi" --ondisk=vda --size=600 --fsoptions="umask=0077,shortname=winnt"
part /boot --fstype="ext4" --ondisk=vda --size=1024
part btrfs.114 --fstype="btrfs" --ondisk=vda --grow --maxsize=10000000000000 # Some really large value since we want the partition to take all left over space.
btrfs none --label=photonponyos --data=single btrfs.114
btrfs / --subvol --name=root LABEL=photonponyos
btrfs /home --subvol --name=home LABEL=photonponyos
btrfs /opt/webcache --subvol --name=opt_webcache LABEL=photonponyos
btrfs /opt --subvol --name=opt LABEL=photonponyos
btrfs /usr/local --subvol --name=usr_local LABEL=photonponyos

# System timezone
timezone Europe/Berlin --utc

#Root password
rootpw --lock
user --groups=wheel --name=fabian --password=$y$j9T$0EF1wDrjYvNDtiG1vc8AKH4e$8lIjOhWZlgHy/7jZtksK9dYxXUECxWDRP6ZpJg2BtpC --iscrypted --gecos="fabian"

# Make sure SELinux is enabled
selinux --enforcing
