How the images are built:

Each image is built automatically in the
[anyvm-org/hurd-builder](https://github.com/anyvm-org/hurd-builder)
repo's GitHub Actions: it downloads the official Debian GNU/Hurd
pre-installed disk image, customizes it (serial console, ssh,
first-boot setup), boots it in QEMU, pre-installs the packages listed
in the conf, and exports the disk as a compressed qcow2 image. No
interactive installer is run.

Upstream media: the official Debian GNU/Hurd images from
https://cdimage.debian.org/cdimage/ports/latest/ (port page:
https://www.debian.org/ports/hurd/).
