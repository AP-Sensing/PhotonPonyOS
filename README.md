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
