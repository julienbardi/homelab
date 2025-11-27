# mk/generate.mk
SCRIPTS := $(notdir $(wildcard scripts/*.sh))
strip_sh = $(patsubst %.sh,%,$(1))

INSTALL_TARGETS :=
UNINSTALL_TARGETS :=

$(foreach s,$(SCRIPTS),\
  $(eval NAME := $(call strip_sh,$(s)))\
  $(eval SRC := scripts/$(s))\
  $(eval FILE := $(INSTALL_PATH)/$(NAME))\
  $(eval INSTALL_TARGETS += install-$(NAME))\
  $(eval UNINSTALL_TARGETS += uninstall-$(NAME))\
  $(eval $(FILE): ; $(call install_script,$(SRC),$(NAME)))\
  $(eval .PHONY: install-$(NAME))\
  $(eval install-$(NAME): $(FILE))\
  $(eval .PHONY: uninstall-$(NAME))\
  $(eval uninstall-$(NAME): ; $(call uninstall_script,$(NAME)))\
)

.PHONY: install-all uninstall-all
install-all: $(INSTALL_TARGETS)
uninstall-all: $(UNINSTALL_TARGETS)
