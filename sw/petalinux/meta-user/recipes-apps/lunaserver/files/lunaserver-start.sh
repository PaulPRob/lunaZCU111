#!/bin/sh
# lunaserver-start.sh - start the capture server on the ZCU111
#
# - makes sure eth0 has the static address 192.168.2.10/24 (fallback if the
#   PetaLinux network configuration did not set it)
# - keeps the configuration on the SD card boot partition so that it
#   survives reboots (the root file system is an initramfs)
IP=192.168.2.10/24

# UIO driver for the generic-uio nodes (trigger core, DMA, GPIO, DMA buffer)
# and for librfdc/libmetal.  It is built in (luna.cfg); this modprobe is only a
# fallback in case a kernel config makes it a module (no autoload for generic-uio).
modprobe uio_pdrv_genirq of_id=generic-uio 2>/dev/null || true
SD=/dev/mmcblk0p1
CONF_DIR=/mnt/sd

ip link set eth0 up 2>/dev/null
if ! ip -4 addr show eth0 | grep -q "inet ${IP%/*}/"; then
    ip addr add "$IP" dev eth0 2>/dev/null
fi

CONF=/etc/lunaserver.conf
if [ -b "$SD" ]; then
    mkdir -p "$CONF_DIR"
    grep -q " $CONF_DIR " /proc/mounts || mount "$SD" "$CONF_DIR" 2>/dev/null
    grep -q " $CONF_DIR " /proc/mounts && CONF="$CONF_DIR/lunaserver.conf"
fi

exec /usr/bin/lunaserver -c "$CONF" "$@"
