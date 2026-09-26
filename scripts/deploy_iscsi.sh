#!/usr/bin/env bash
set -euo pipefail

ZVOL="tank/game-lun"
BACKSTORE="gamebackend"
TARGET="iqn.2026-09.ch.bardi:pve.game"
INITIATOR="iqn.1991-05.com.microsoft:omen30l-20250504"

# IPv4 + IPv6 portals (exported from Makefile)
LAN_NAS="${LAN_NAS:-10.89.12.4}"
LAN6_NAS="${LAN6_NAS:-fd89:7a3b:42c0::4}"

echo "Ensuring ZFS zvol exists: ${ZVOL}"
if ! zfs list "${ZVOL}" >/dev/null 2>&1; then
    echo "Creating zvol ${ZVOL} (4T, lz4, 16K)"
    zfs create -V 4T -o compression=lz4 -o volblocksize=16K "${ZVOL}"
else
    echo "Zvol ${ZVOL} already exists"
fi

echo "Ensuring targetcli is installed"
if ! dpkg -s targetcli-fb >/dev/null 2>&1; then
    apt update && apt install -y targetcli-fb
else
    echo "targetcli-fb already installed"
fi

echo "Ensuring iSCSI backstore exists"
if [ ! -d "/sys/kernel/config/target/core/block_${BACKSTORE}" ]; then
    echo "Creating backstore ${BACKSTORE}"
    targetcli /backstores/block create name=${BACKSTORE} dev=/dev/zvol/${ZVOL} || true
else
    echo "Backstore ${BACKSTORE} already exists"
fi

echo "Ensuring iSCSI target exists"
if [ ! -d "/sys/kernel/config/target/iscsi/${TARGET}" ]; then
    echo "Creating target ${TARGET}"
    targetcli /iscsi create ${TARGET} || true
else
    echo "Target ${TARGET} already exists"
fi

echo "Ensuring LUN exists"
if [ ! -L "/sys/kernel/config/target/iscsi/${TARGET}/tpg1/luns/lun_0" ]; then
    echo "Creating LUN lun_0"
    targetcli /iscsi/${TARGET}/tpg1/luns create storage_object=${BACKSTORE} || true
else
    echo "LUN lun_0 already exists"
fi

echo "Ensuring ACL exists"
if [ ! -d "/sys/kernel/config/target/iscsi/${TARGET}/tpg1/acls/${INITIATOR}" ]; then
    echo "Creating ACL for initiator ${INITIATOR}"
    targetcli /iscsi/${TARGET}/tpg1/acls create ${INITIATOR} || true
else
    echo "ACL already exists"
fi

echo "Ensuring IPv4 portal exists"
if [ ! -d "/sys/kernel/config/target/iscsi/${TARGET}/tpg1/np/${LAN_NAS}:3260" ]; then
    echo "Creating IPv4 portal ${LAN_NAS}"
    targetcli /iscsi/${TARGET}/tpg1/portals create ${LAN_NAS} || true
else
    echo "IPv4 portal already exists"
fi

echo "Ensuring IPv6 portal exists"
if [ ! -d "/sys/kernel/config/target/iscsi/${TARGET}/tpg1/np/[${LAN6_NAS}]:3260" ]; then
    echo "Creating IPv6 portal ${LAN6_NAS}"
    targetcli /iscsi/${TARGET}/tpg1/portals create ${LAN6_NAS} || true
else
    echo "IPv6 portal already exists"
fi

echo "Saving iSCSI configuration"
targetcli saveconfig
echo "iSCSI configuration successfully applied."
