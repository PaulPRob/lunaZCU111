#!/usr/bin/env bash
# rebuild the PetaLinux images and BOOT.BIN for an existing project
set -e
cd "$(dirname "$0")/lunaZCU111-plnx"
source ~/Xilinx/Petalinux/2023.2/settings.sh >/dev/null
petalinux-build
petalinux-package --boot --force --u-boot \
    --fsbl images/linux/zynqmp_fsbl.elf --fpga images/linux/system.bit
echo "IMAGES_DONE"
