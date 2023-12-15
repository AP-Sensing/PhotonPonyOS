![PhotonPonyOS](branding/ppos.svg)

A fork of https://gitlab.com/fedora/ostree/ci-test that includes everything related to building our custom [Fedora Silverblue](https://fedoraproject.org/silverblue/) based PhotonPonyOS.
The instructions are for building the boot iso image that contains the [Anaconda Fedora installer](https://fedoraproject.org/wiki/Anaconda).

### Requirements

Requires an up to date Fedora >= 38.

```bash
sudo dnf install just ostree rpm-ostree lorax
```

### Building

```bash
git clone https://github.com/AP-Sensing/PhotonPonyOS.git
cd PhotonPonyOS
sudo just compose photon-pony
sudo just lorax photon-pony
```
 
After successfully building, the image will be located in `iso/linux/images/boot.iso`.
This image then can be flashed to a USB-stick with for example the [Fedora Media Writer](https://flathub.org/apps/org.fedoraproject.MediaWriter).


### Gitlab CI automation

PPOS can be build in a Gitlab-Runner using a Docker-Executor.
The loop module has to be loaded on the host of the GitLab-Runner. This can be done via:
```bash
sudo modprobe loop
```

The Gitlab configuration file can be found at `/etc/gitlab-runner/config.toml`.
```toml
  [runners.docker]
    image = "fedora:38"
    privileged = true
```
Since building the image requires read/write permissions on mounted devices (e.g. `/dev/loop0`), docker images using it need to be marked as `privileged`.
