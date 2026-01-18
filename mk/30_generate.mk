# mk/30_generate.mk

SCRIPTS := $(notdir $(wildcard $(HOMELAB_DIR)/scripts/*.sh))
FILES   := $(addprefix $(INSTALL_PATH)/,$(SCRIPTS))

.PHONY: install-all uninstall-all

install-all: $(FILES)

uninstall-all:
		@for s in $(SCRIPTS); do \
				$(call uninstall_script,$$s); \
		done
