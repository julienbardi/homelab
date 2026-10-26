# mk/40_iscsi-game-drive.mk

.PHONY: iscsi-game-drive iscsi-remove iscsi-status

iscsi-game-drive: install-all
	@$(run_as_root) $(INSTALL_PATH)/deploy_iscsi.sh

iscsi-remove:
	@echo "Removing iSCSI configuration and ZFS zvol..."
	@sudo targetcli /iscsi delete iqn.2026-09.ch.bardi:pve.game 2>/dev/null || echo "iSCSI target does not exist"
	@sudo targetcli /backstores/block delete gamebackend 2>/dev/null || echo "Backstore does not exist"
	@sudo zfs destroy tank/game-lun 2>/dev/null || echo "ZFS zvol tank/game-lun does not exist"
	@sudo targetcli saveconfig
	@echo "iSCSI game drive fully removed."

iscsi-status:
	@echo "=== iSCSI Game Drive Status ==="
	@echo "ZFS Zvol:"
	@sudo zfs list tank/game-lun || echo "  -> Not found"
	@echo ""
	@echo "Targetcli Backstores:"
	@sudo targetcli /backstores/block ls || echo "  -> Not found"
	@echo ""
	@echo "Targetcli iSCSI Tree:"
	@sudo targetcli /iscsi ls || echo "  -> Not found"