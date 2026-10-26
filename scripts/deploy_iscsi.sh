#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="deploy_iscsi"

source /usr/local/bin/common.sh

ZVOL="tank/game-lun"
BACKSTORE="gamebackend"
TARGET="iqn.2026-09.ch.bardi:pve.game"
INITIATOR="iqn.1991-05.com.microsoft:omen30l-20250504"

LAN_NAS="${LAN_NAS:-10.89.12.4}"
LAN6_NAS="${LAN6_NAS:-fd89:7a3b:42c0::4}"

CHECK_ONLY=0
CHANGED=0

if [ "${1:-}" = "--check" ]; then
	CHECK_ONLY=1
fi

mark_changed() {
	CHANGED=1
}

ensure() {
	if [ "$CHECK_ONLY" -eq 1 ]; then
		recon_error "$1"
		exit 1
	fi
}

create_or_fail() {
	local description="$1"
	shift

	ensure "${description}"

	"$@"

	mark_changed
}

recon_banner "iSCSI Game Drive"

#
# ZFS zvol
#

recon_check "ZVOL"

if zfs list "${ZVOL}" >/dev/null 2>&1; then
	recon_verified "ZVOL" "${ZVOL}"
else
	create_or_fail "zvol missing" \
		zfs create \
			-V 4T \
			-o compression=lz4 \
			-o volblocksize=16K \
			"${ZVOL}"

	recon_created "ZVOL" "${ZVOL}"
fi

#
# Package
#

recon_check "Package"

if dpkg -s targetcli-fb >/dev/null 2>&1; then
	recon_verified "Package" "targetcli-fb"
else
	ensure "targetcli-fb missing"

	apt update
	apt install -y targetcli-fb

	mark_changed

	recon_created "Package" "targetcli-fb"
fi

#
# State snapshots
#

TARGETCLI_BACKSTORES="$(targetcli /backstores/block ls 2>/dev/null || true)"
TARGETCLI_ISCSI="$(targetcli /iscsi ls 2>/dev/null || true)"

#
# Backstore
#

recon_check "Backstore"

if echo "${TARGETCLI_BACKSTORES}" | grep -Fq "${BACKSTORE}"; then

	if ! echo "${TARGETCLI_BACKSTORES}" | grep -Fq "/dev/zvol/${ZVOL}"; then
		recon_error \
			"Backstore ${BACKSTORE} points to unexpected device"
		exit 1
	fi

	recon_verified "Backstore" "${BACKSTORE}"

else

	create_or_fail "backstore missing" \
		targetcli /backstores/block create \
			name="${BACKSTORE}" \
			dev="/dev/zvol/${ZVOL}"

	recon_created "Backstore" "${BACKSTORE}"
fi

#
# Target
#

recon_check "Target"

if echo "${TARGETCLI_ISCSI}" | grep -Fq "${TARGET}"; then
	recon_verified "Target" "${TARGET}"
else
	create_or_fail "target missing" \
		targetcli /iscsi create "${TARGET}"

	recon_created "Target" "${TARGET}"
fi

#
# LUN
#

LUNS="$(targetcli /iscsi/${TARGET}/tpg1/luns ls 2>/dev/null || true)"

recon_check "LUN"

if echo "${LUNS}" | grep -Fq "${BACKSTORE}"; then
	recon_verified "LUN" "${BACKSTORE}"
else
	create_or_fail "LUN missing" \
		targetcli \
			/iscsi/"${TARGET}"/tpg1/luns \
			create \
			"/backstores/block/${BACKSTORE}"

	recon_created "LUN" "${BACKSTORE}"
fi

#
# ACL
#

ACLS="$(targetcli /iscsi/${TARGET}/tpg1/acls ls 2>/dev/null || true)"

recon_check "ACL"

if echo "${ACLS}" | grep -Fq "${INITIATOR}"; then
	recon_verified "ACL" "${INITIATOR}"
else
	create_or_fail "ACL missing" \
		targetcli \
			/iscsi/"${TARGET}"/tpg1/acls \
			create \
			"${INITIATOR}"

	recon_created "ACL" "${INITIATOR}"
fi

#
# Portals
#

PORTALS="$(targetcli /iscsi/${TARGET}/tpg1/portals ls 2>/dev/null || true)"

recon_check "IPv4 Portal"

if echo "${PORTALS}" | grep -Fq "0.0.0.0:3260"; then
	recon_verified "IPv4 Portal" "0.0.0.0:3260"
else
	create_or_fail "IPv4 portal missing" \
		targetcli \
			/iscsi/"${TARGET}"/tpg1/portals \
			create \
			"${LAN_NAS}"

	recon_created "IPv4 Portal" "${LAN_NAS}:3260"
fi

PORTALS="$(targetcli /iscsi/${TARGET}/tpg1/portals ls 2>/dev/null || true)"

recon_check "IPv6 Portal"

if echo "${PORTALS}" | grep -Fq "[${LAN6_NAS}]:3260"; then
	recon_verified "IPv6 Portal" "[${LAN6_NAS}]:3260"
else
	create_or_fail "IPv6 portal missing" \
		targetcli \
			/iscsi/"${TARGET}"/tpg1/portals \
			create \
			"${LAN6_NAS}"

	recon_created "IPv6 Portal" "[${LAN6_NAS}]:3260"
fi

#
# Summary
#

recon_summary

if [ "$CHECK_ONLY" -eq 1 ]; then
	recon_success "Configuration converged"
	exit 0
fi

if [ "$CHANGED" -eq 1 ]; then
	targetcli saveconfig >/dev/null
	recon_success "Saved targetcli configuration"
else
	recon_success "Configuration already converged"
fi

if [ "$RECON_CREATED" -gt 0 ]; then

	echo
	echo "Next steps for operator (Windows: Omen30l-20250504):"
	echo "  1. Open 'iSCSI Initiator' on Windows."
	echo "  2. Go to 'Discovery' -> 'Add Portal' -> enter the PVE host IP address."
	echo "  3. Go to 'Targets' -> select iqn.2026-09.ch.bardi:pve.game -> Connect."
	echo "  4. Open 'Disk Management' -> initialize disk (GPT) -> create NTFS volume."
	echo "  5. (Optional) Add PrimoCache L1/L2 caching."
	echo
	echo "Drive is now ready for use on Omen30l-20250504."

fi