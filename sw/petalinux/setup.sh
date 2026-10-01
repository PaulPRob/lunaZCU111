#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup.sh - create and build the PetaLinux 2023.2 project for lunaZCU111
#
#   sw/petalinux/setup.sh [--bsp /path/xilinx-zcu111-v2023.2-final.bsp] [--no-build]
#
# Prerequisites
#   * PetaLinux 2023.2 installed (default ~/Xilinx/PetaLinux/2023.2)
#   * hw/build/lunaZCU111.xsa  (vivado -mode batch -source hw/scripts/build.tcl)
#
# Result: sw/petalinux/lunaZCU111-plnx/images/linux/{BOOT.BIN,image.ub,boot.scr}
#         -> copy these three files to the FAT partition of the SD card.
# -----------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$HERE/../.." && pwd)"
if [[ -z "${PLNX_SETTINGS:-}" ]]; then
    for d in "$HOME/Xilinx/PetaLinux/2023.2" "$HOME/Xilinx/Petalinux/2023.2"; do
        [[ -f "$d/settings.sh" ]] && PLNX_SETTINGS="$d/settings.sh" && break
    done
fi
PLNX_SETTINGS="${PLNX_SETTINGS:-$HOME/Xilinx/PetaLinux/2023.2/settings.sh}"
XSA="${XSA:-$TOP/hw/build/lunaZCU111.xsa}"
NAME=lunaZCU111-plnx
PROJ="$HERE/$NAME"
BSP=""
BUILD=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bsp) BSP="$2"; shift 2 ;;
        --no-build) BUILD=0; shift ;;
        *) echo "unknown option $1"; exit 1 ;;
    esac
done

[[ -f "$PLNX_SETTINGS" ]] || { echo "PetaLinux settings not found: $PLNX_SETTINGS"; exit 1; }
[[ -f "$XSA" ]] || { echo "XSA not found: $XSA (build the hardware first)"; exit 1; }
[[ "$(readlink -f /bin/sh)" == */bash ]] || { echo "/bin/sh must be bash: sudo dpkg-reconfigure dash -> No"; exit 1; }

# shellcheck disable=SC1090
source "$PLNX_SETTINGS"

cd "$HERE"
if [[ ! -d "$PROJ" ]]; then
    if [[ -n "$BSP" ]]; then
        petalinux-create -t project -s "$BSP" -n "$NAME"
    else
        petalinux-create -t project --template zynqMP -n "$NAME"
    fi
fi
cd "$PROJ"

petalinux-config --get-hw-description="$XSA" --silentconfig

# ---------------------------------------------------------------- config ----
CFG=project-spec/configs/config
set_cfg() {   # set_cfg KEY VALUE   (VALUE "n" -> "is not set")
    sed -i "/^$1=/d; /^# $1 is not set/d" "$CFG"
    if [[ "$2" == n ]]; then echo "# $1 is not set" >> "$CFG"; else echo "$1=$2" >> "$CFG"; fi
}
set_cfg CONFIG_SUBSYSTEM_MACHINE_NAME '"zcu111-reva"'
set_cfg CONFIG_SUBSYSTEM_ETHERNET_PSU_ETHERNET_3_SELECT y
set_cfg CONFIG_SUBSYSTEM_ETHERNET_PSU_ETHERNET_3_USE_DHCP n
set_cfg CONFIG_SUBSYSTEM_ETHERNET_PSU_ETHERNET_3_IP_ADDRESS '"192.168.2.10"'
set_cfg CONFIG_SUBSYSTEM_ETHERNET_PSU_ETHERNET_3_IP_NETMASK '"255.255.255.0"'
set_cfg CONFIG_SUBSYSTEM_ETHERNET_PSU_ETHERNET_3_IP_GATEWAY '"192.168.2.1"'
set_cfg CONFIG_SUBSYSTEM_HOSTNAME '"luna-zcu111"'
set_cfg CONFIG_SUBSYSTEM_PRODUCT '"lunaZCU111"'
# full root file system inside image.ub (SD card needs only BOOT.BIN,
# boot.scr and image.ub); UIO binding for the generic-uio nodes
set_cfg CONFIG_SUBSYSTEM_ROOTFS_INITRD n
set_cfg CONFIG_SUBSYSTEM_ROOTFS_INITRAMFS y
set_cfg CONFIG_SUBSYSTEM_INITRAMFS_IMAGE_NAME '"petalinux-image-minimal"'
set_cfg CONFIG_SUBSYSTEM_EXTRA_BOOTARGS '"cpuidle.off=1 uio_pdrv_genirq.of_id=generic-uio"'
# limit parallelism (16-24 GB WSL2 host): bitbake tasks and make jobs
set_cfg CONFIG_YOCTO_BB_NUMBER_THREADS '"6"'
set_cfg CONFIG_YOCTO_PARALLEL_MAKE '"6"'

# --------------------------------------------------------------- meta-user --
MU=project-spec/meta-user
cp "$HERE/meta-user/recipes-bsp/device-tree/files/system-user.dtsi" \
   "$MU/recipes-bsp/device-tree/files/system-user.dtsi"
mkdir -p "$MU/recipes-kernel/linux/linux-xlnx" "$MU/recipes-apps/lunaserver/files/src"
cp "$HERE/meta-user/recipes-kernel/linux/linux-xlnx/luna.cfg" "$MU/recipes-kernel/linux/linux-xlnx/"
# append our kernel fragment to the (BSP) bbappend instead of replacing it
KB="$MU/recipes-kernel/linux/linux-xlnx_%.bbappend"
if [[ ! -f "$KB" ]]; then
    echo 'FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"' > "$KB"
fi
grep -q "luna.cfg" "$KB" || printf '\nSRC_URI:append = " file://luna.cfg"\nKERNEL_FEATURES:append = " luna.cfg"\n' >> "$KB"
cp "$HERE/meta-user/recipes-apps/lunaserver/lunaserver.bb" "$MU/recipes-apps/lunaserver/"
cp "$HERE"/meta-user/recipes-apps/lunaserver/files/lunaserver.{init,service} \
   "$HERE/meta-user/recipes-apps/lunaserver/files/lunaserver-start.sh" \
   "$MU/recipes-apps/lunaserver/files/"
# server sources
rm -rf "$MU/recipes-apps/lunaserver/files/src"
mkdir -p "$MU/recipes-apps/lunaserver/files/src"
cp "$TOP"/sw/server/*.[ch] "$TOP/sw/server/Makefile" "$MU/recipes-apps/lunaserver/files/src/"

# U-Boot: the kernel with the embedded root file system is ~110 MB uncompressed,
# more than the ZynqMP default CONFIG_SYS_BOOTM_LEN (0x6400000 = 100 MiB)
UB="$MU/recipes-bsp/u-boot"
mkdir -p "$UB/files"
if [[ ! -f "$UB/u-boot-xlnx_%.bbappend" ]]; then
    printf 'FILESEXTRAPATHS:prepend := "${THISDIR}/files:"\n\nSRC_URI:append = " file://bsp.cfg"\n' > "$UB/u-boot-xlnx_%.bbappend"
fi
grep -q "file://bsp.cfg" "$UB/u-boot-xlnx_%.bbappend" || echo 'SRC_URI:append = " file://bsp.cfg"' >> "$UB/u-boot-xlnx_%.bbappend"
touch "$UB/files/bsp.cfg"
sed -i '/CONFIG_SYS_BOOTM_LEN/d' "$UB/files/bsp.cfg"
echo "CONFIG_SYS_BOOTM_LEN=0x10000000" >> "$UB/files/bsp.cfg"

# rootfs packages
UR="$MU/conf/user-rootfsconfig"
RF=project-spec/configs/rootfs_config
for pkg in lunaserver rfdc libmetal i2c-tools ethtool iperf3; do
    grep -q "^CONFIG_$pkg\$" "$UR" || echo "CONFIG_$pkg" >> "$UR"
done
petalinux-config -c rootfs --silentconfig
for pkg in lunaserver rfdc libmetal i2c-tools ethtool iperf3; do
    sed -i "/^CONFIG_$pkg=/d; /^# CONFIG_$pkg is not set/d" "$RF"
    echo "CONFIG_$pkg=y" >> "$RF"
done
petalinux-config -c rootfs --silentconfig
petalinux-config --silentconfig

if [[ $BUILD -eq 0 ]]; then
    echo "project prepared in $PROJ (not built)"
    exit 0
fi

petalinux-build
petalinux-package --boot --force --u-boot \
    --fsbl images/linux/zynqmp_fsbl.elf --fpga images/linux/system.bit
echo
echo "Done. Copy to the SD card FAT partition:"
echo "  $PROJ/images/linux/BOOT.BIN"
echo "  $PROJ/images/linux/image.ub"
echo "  $PROJ/images/linux/boot.scr"
echo "Set ZCU111 boot switch SW6 for SD boot: SW6[4:1] = OFF,OFF,OFF,ON (mode 1110, UG1271 table 2-4)."
