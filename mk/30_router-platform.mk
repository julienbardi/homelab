# mk/platform.mk
# ------------------------------------------------------------
# PLATFORM — SHELL ABI & BOOTSTRAP
# ------------------------------------------------------------

.NOTPARALLEL: deploy-common

.PHONY: deploy-common
deploy-common:
	$(call deploy_if_changed,$(COMMON_SH_SRC),$(COMMON_SH_DST))
