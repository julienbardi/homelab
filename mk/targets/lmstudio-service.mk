# LM Studio systemd user service deployment

.PHONY: lmstudio-service
lmstudio-service:
ifeq ($(LMSTUDIO_ALLOWED),1)
	@echo "[lmstudio] Installing systemd user service"
	mkdir -p ~/.config/systemd/user
	cp tools/lmstudio/lmstudio.service ~/.config/systemd/user/
	systemctl --user daemon-reload
	systemctl --user enable --now lmstudio.service
else
	@echo "[lmstudio] Skipped: service allowed only on Omen30l-* under WSL2"
endif
