![PhotonPonyOS](branding/ppos.svg)

A fork of https://gitlab.com/fedora/ostree/ci-test that includes everything related to building our custom [Fedora Silverblue](https://fedoraproject.org/silverblue/) based PhotonPonyOS.
The instructions are for building the boot iso image that contains the [Anaconda Fedora installer](https://fedoraproject.org/wiki/Anaconda).

Provides support for building new `ostree` commits and based on those, new `rpm-ostree` OS releases that can be offered as online (via a mirror) or offline (single zip file) update.
Also supports generating bootable (kickstarted) ISO files using the [Anaconda Fedora installer](https://fedoraproject.org/wiki/Anaconda).

### ⚠️ Important Note ⚠️

The build system used here is Open Source, but the resulting operating system (PhotonPonyOS) is not strictly speaking since it contains proprietary packages developed and distributed by AP Sensing.
For building the most variants of the operating system, you need access to the internal AP Sensing network to get access to the AP Sensing RPM mirrors.

## Features

Here is a list of all (non standard) features PPOS provides:
* `Secure Boot` - Installing from the generated boot ISO enables secure boot by default. For this all kernel modules used get signed with our own AP Sensing GPG key that acts as root of trust in this case.
* `LUKS Disk Encryption` - By default all partitions are encrypted using LUKS.
* `LUKS Key Stored Inside The TPM` - After a successful setup, the LUKS key is stored inside the TPM and bound to the [`PCR7` (Secure Boot State)](https://wiki.archlinux.org/title/Trusted_Platform_Module) register. This allows booting the system without having to enter the LUKS password.
* `BTRFS Subvolumes` - We heavily use BTRFS subvolumes to easily backup and restore non-read-only parts of the file system like the device configuration to allow a factory reset of the device.

## Requirements

Requires an up to date Fedora >= 38.
You also need the same `kernel-devel` version installed on your system as for the one you are building the `ostree` commit.
Else compiling kernel modules will fail using akmod during building a new `ostree` commit.

```bash
sudo dnf update
sudo dnf install just ostree rpm-ostree lorax kernel-devel
```

## Building

```bash
git clone https://github.com/AP-Sensing/PhotonPonyOS.git
cd PhotonPonyOS
sudo just compose photon-pony
sudo just lorax photon-pony
```
 
After successfully building, the image will be located in `iso/linux/images/boot.iso`.
This image then can be flashed onto a USB-stick with for example the [Fedora Media Writer](https://flathub.org/apps/org.fedoraproject.MediaWriter).


## Gitlab CI automation

PPOS can be build in a Gitlab-Runner using a Docker-Executor.
The loop module has to be loaded on the host of the GitLab-Runner. This can be done via:
```bash
sudo modprobe loop
```

Since building the image requires read/write permissions on mounted (loop-) devices (e.g. `/dev/loop0`), docker images using it need to be marked as `privileged`.
The GitLab runner configuration is located at: `/etc/gitlab-runner/config.toml`
```toml
  [runners.docker]
    image = "fedora:38"
    privileged = true
```
Since building the image requires read/write permissions on mounted devices (e.g. `/dev/loop0`), docker images using it need to be marked as `privileged`.
