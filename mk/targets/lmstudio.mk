# LM Studio install target (WSL2 + Omen30l contract)

HOSTNAME ?= $(shell hostname)

ifeq ($(findstring Omen30l,$(HOSTNAME)),Omen30l)
HOST_MATCH := 1
else
HOST_MATCH := 0
endif

ifeq ($(WSL2_ENV)$(HOST_MATCH),11)
LMSTUDIO_ALLOWED := 1
else
LMSTUDIO_ALLOWED := 0
endif

.PHONY: lmstudio
lmstudio:
ifeq ($(LMSTUDIO_ALLOWED),1)
	@echo "[lmstudio] Installing LM Studio on $(HOSTNAME) (WSL2 verified)"
	tools/lmstudio/install.sh
else
	@echo "[lmstudio] Skipped: allowed only on Omen30l-* under WSL2"
endif
