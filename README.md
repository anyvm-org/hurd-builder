

[![Build](https://github.com/anyvm-org/hurd-builder/actions/workflows/build.yml/badge.svg)](https://github.com/anyvm-org/hurd-builder/actions/workflows/build.yml)

Latest: v2.0.0


The image builder for `hurd`


All the supported releases are here:



| Release | x86_64 (amd64) | i386 |
|---------|---------|---------|
| 2025 | ✅ (rsync,scp,nfs,tar) | ✅ (rsync,scp,nfs,tar) |

<!-- arch-label: x86_64 = x86_64 (amd64) -->

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




How to build:

1. Use the [manual.yml](.github/workflows/manual.yml) to build manually.
   
    Run the workflow manually, you will get a view-only webconsole from the output of the workflow, just open the link in your web browser.
   
    You will also get an interactive VNC connection port from the output, you can connect to the vm by any vnc client.

2. Run the builder locally on your Ubuntu machine.

    Just clone the repo. and run:
    ```bash
    python3 build.py conf/hurd-2025.conf
    ```
   
