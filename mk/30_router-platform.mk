# mk/30_router-platform.mk
# PLATFORM — SHELL ABI CONVERGENCE
.PHONY: deploy-common
deploy-common:
	@$(INSTALL_FILE_IF_CHANGED) "" "" $(COMMON_SH_SRC) "" "" $(COMMON_SH_DST) root root 0755
