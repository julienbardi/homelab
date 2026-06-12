# LM Studio uninstall target

.PHONY: lmstudio-uninstall
lmstudio-uninstall:
ifeq ($(LMSTUDIO_ALLOWED),1)
	@echo "[lmstudio] Uninstalling LM Studio"
	tools/lmstudio/uninstall.sh
else
	@echo "[lmstudio] Skipped: uninstall allowed only on Omen30l-* under WSL2"
endif
