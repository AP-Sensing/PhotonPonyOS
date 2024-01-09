![PhotonPonyOS](branding/ppos.svg)

A fork of https://gitlab.com/fedora/ostree/ci-test that includes everything related to building our custom [Fedora Silverblue](https://fedoraproject.org/silverblue/) based PhotonPonyOS (PPOS).

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
sudo just compose n62-default
sudo just lorax n62-default
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

## Release Naming

The following illustrates the release branch naming further and lists all currently in use branches.

```
ppos/{n62,n5x}/{default,base}/{prod,staging,dev}/{x86_64,aarch64,...}
│    │         │              │                  │
│    │         │              │                  └── The hardware architecture this branch is targeting.
│    │         │              │
│    │         │              └── The type of release. 'prod' for a production ready release shipped to customers. Everything is for in-house releases and development builds.
│    │         │
│    │         └── The version of the OS defining which features and packages are included.
│    │
│    └── The product we are targeting with this OS build.
│
└── A fixed prefix to identify PhotonPonyOS
```

### Active Branches

The following active branches are currently in use and are supported with updates.

#### `/ppos/n62/base/{prod,staging,dev}/x86_64`

Represents the base image without any of the measurement specific software.
Used during development to more easily allow layering local dev packages onto the base commit.  

#### `/ppos/n62/default/{prod,staging,dev}/x86_64`

Takes `/ppos/n62/base/{prod,staging,dev}/x86_64` as base and extends it with all RPM packages required for a functioning measurement device.
