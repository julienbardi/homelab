# Orchestration target for LM Studio

.PHONY: lmstudio-all
lmstudio-all: lmstudio lmstudio-service
	@echo "[lmstudio] Full LM Studio pipeline completed"
