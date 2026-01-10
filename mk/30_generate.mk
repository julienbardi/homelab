# mk/30_generate.mk
# Usage: make install-all
SCRIPTS := $(notdir $(wildcard scripts/*.sh))
strip_sh = $(patsubst %.sh,%,$(1))

INSTALL_TARGETS :=
UNINSTALL_TARGETS :=

$(foreach s,$(SCRIPTS),\
  $(eval NAME := $(s))\
  $(eval SRC := scripts/$(s))\
  $(eval FILE := $(INSTALL_PATH)/$(NAME))\
  $(eval INSTALL_TARGETS += install-$(NAME))\
  $(eval UNINSTALL_TARGETS += uninstall-$(NAME))\
  $(eval $(FILE): ensure-run-as-root ; $(call install_script,$(SRC),$(NAME)))\
  $(eval .PHONY: install-$(NAME))\
  $(eval install-$(NAME): $(FILE))\
  $(eval .PHONY: uninstall-$(NAME))\
  $(eval uninstall-$(NAME): ensure-run-as-root ; $(call uninstall_script,$(NAME)))\
)

.PHONY: install-all uninstall-all
install-all: $(INSTALL_TARGETS)
uninstall-all: $(UNINSTALL_TARGETS)
