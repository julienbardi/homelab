# --------------------------------------------------------------------
# mk/01_common.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Defines run_as_root := ./bin/run-as-root
# - All recipes must call $(run_as_root) with argv tokens.
# - Do not wrap entire command in quotes.
# - Escape operators (\>, \|, \&\&, \|\|) so they survive Make parsing.
# --------------------------------------------------------------------
# Script naming contract:
# - Script filenames (including .sh) are preserved verbatim at install time.
# - No extension stripping or renaming occurs.
# - Example:
#     scripts/foo.sh → /usr/local/bin/foo.sh
#     scripts/bar.sh → /usr/local/sbin/bar.sh


# Fallback for recursive make (do not force; let make set it if present)
MAKE ?= $(MAKE)

run_as_root := $(HOMELAB_DIR)/bin/run-as-root

.PHONY: ensure-run-as-root
ensure-run-as-root:
	@if [ ! -x "$(run_as_root)" ]; then \
		chmod +x $(run_as_root); \
	fi

INSTALL_PATH ?= /usr/local/bin
INSTALL_SBIN_PATH ?= /usr/local/sbin

OWNER ?= root
GROUP ?= root
MODE ?= 0755

# Stamp dir (overridable)
STAMP_DIR ?= /var/lib/homelab

# log(message). Show on screen and write to syslog/journald
define log
	echo "$1" >&2; command -v logger >/dev/null 2>&1 && logger -t homelab-make "$1"
endef


# Bootstrap install for install_if_changed.sh (cannot use itself), -C means "copy only if contents differ".
define install_install_if_changed
	@$(run_as_root) install -C -o $(OWNER) -g $(GROUP) -m $(MODE) \
		scripts/install_if_changed.sh \
		$(INSTALL_PATH)/install_if_changed.sh
endef

$(INSTALL_PATH)/install_if_changed.sh: ensure-run-as-root scripts/install_if_changed.sh
	$(call install_install_if_changed)

# install_script(src, name), exit code 0 (unchanged) and 3 (updated) are success
define install_script
	@$(run_as_root) $(INSTALL_PATH)/install_if_changed.sh --quiet \
		$(1) $(INSTALL_PATH)/$(2) $(OWNER) $(GROUP) $(MODE) || [ $$? -eq 3 ]
endef

# uninstall_script(name)
define uninstall_script
	@$(run_as_root) rm -f $(INSTALL_PATH)/$(1)
endef

# --------------------------------------------------------------------
# apt update caching helper
# - Avoid running apt-get update on every apt_install invocation.
# - APT_UPDATE_MAX_AGE is in seconds (default 6 hours).
# - Stamp file is written as root so subsequent runs by non-root users still see it.
# --------------------------------------------------------------------
APT_UPDATE_STAMP ?= $(STAMP_DIR)/apt.update.stamp
APT_UPDATE_MAX_AGE ?= 21600		# 6 hours in seconds

define apt_update_if_needed
	$(run_as_root) mkdir -p --mode=0755 $(STAMP_DIR) >/dev/null 2>&1 || true; \
	if [ ! -f "$(APT_UPDATE_STAMP)" ] || [ $$(expr $$(date +%s) - $$(stat -c %Y "$(APT_UPDATE_STAMP)" 2>/dev/null || echo 0) ) -gt $(APT_UPDATE_MAX_AGE) ]; then \
		echo "apt-get update (stamp expired)"; \
		$(run_as_root) apt-get update; \
		$(run_as_root) sh -c 'mkdir -p "$(STAMP_DIR)" && date +%s > "$(APT_UPDATE_STAMP)"'; \
	fi
endef

.PHONY: apt-update
apt-update: ensure-run-as-root
	@$(call apt_update_if_needed)

# apt_install(tool, pkg-list)
# - $(1) is the command to check (e.g. curl)
# - $(2) is the apt package(s) to install (e.g. curl)
define apt_install
	if ! PATH=/usr/sbin:/sbin:$$PATH command -v $(1) >/dev/null 2>&1; then \
		echo "$(1) not found, installing: $(2)"; \
		$(call apt_update_if_needed); \
		$(run_as_root) env DEBIAN_FRONTEND=noninteractive \
			apt-get install -y --no-install-recommends \
			-o Dpkg::Options::=--force-confold $(2); \
	else \
		VER_STR=$$( \
			if [ "$(1)" = "strace" ]; then \
				strace -V 2>&1 | head -n1; \
			elif [ "$(1)" = "vnstat" ]; then \
				vnstat --version 2>&1 | head -n1; \
			elif [ "$(1)" = "go" ]; then \
				go version 2>&1 | head -n1; \
			elif [ "$(1)" = "unbound" ]; then \
				PATH=/usr/sbin:/sbin:$$PATH unbound -V 2>&1 | head -n1; \
			else \
				( PATH=/usr/sbin:/sbin:$$PATH $(1) --version 2>&1 || \
				  PATH=/usr/sbin:/sbin:$$PATH $(1) version 2>&1 || \
				  PATH=/usr/sbin:/sbin:$$PATH $(1) -v 2>&1 || \
				  echo "unknown" ) | head -n1; \
			fi \
		); \
		echo "$(1) version: $$VER_STR"; \
	fi
endef



# Usage:
#   $(call apt_remove,packagename)                     -> remove package if present
#   $(call apt_remove,packagename,/path/to/stamp.file) -> remove package and remove stamp; also apt-mark unhold
define apt_remove
	echo "Removing $(1)..."; \
	if dpkg -s $(1) >/dev/null 2>&1; then \
		echo "$(1) is installed; removing..."; \
		$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get remove -y -o Dpkg::Options::=--force-confold $(1) || echo "apt-get remove returned non-zero"; \
		if [ -n "$(2)" ]; then \
			$(run_as_root) apt-mark unhold $(1) >/dev/null 2>&1 || true; \
			$(run_as_root) rm -f $(2) >/dev/null 2>&1 || true; \
		fi; \
	else \
		echo "$(1) not installed; nothing to do"; \
	fi
endef

define remove_cmd
	@echo "Removing $(1)..."
	@$(run_as_root) sh -c '$(2)'
endef

.PHONY: homelab-cleanup-deps
homelab-cleanup-deps: ensure-run-as-root
	@echo "Cleaning up unused dependencies..."
	@$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true

# simple prereq check target (useful in CI)
.PHONY: check-prereqs
check-prereqs:
	@echo "Checking required commands..."; \
	for cmd in sudo apt-get curl git ip wg awk sort mktemp; do \
		command -v $$cmd >/dev/null 2>&1 || { echo "Missing required command: $$cmd"; exit 1; }; \
	done; \
	echo "All required commands present"

# Scripts are installed to /usr/local/bin or /usr/local/sbin based on classification.
# No script is executed directly from the repository.

# pattern rule: install scripts/<name>.sh -> $(INSTALL_PATH)/<name>
# requires install_if_changed.sh to exist first (order-only prerequisite)
$(INSTALL_PATH)/%.sh: $(HOMELAB_DIR)/scripts/%.sh ensure-run-as-root | $(INSTALL_PATH)/install_if_changed.sh
	$(call install_script,$<,$(notdir $<))

$(INSTALL_SBIN_PATH)/%.sh: $(HOMELAB_DIR)/scripts/%.sh ensure-run-as-root | $(INSTALL_PATH)/install_if_changed.sh
	@$(run_as_root) $(INSTALL_PATH)/install_if_changed.sh --quiet \
		$< $@ $(OWNER) $(GROUP) $(MODE) || [ $$? -eq 3 ]


# Script classification:
# - BIN_SCRIPTS  → operator / user-facing tools
# - SBIN_SCRIPTS → root-only system automation
SBIN_SCRIPTS := apt-proxy-auto.sh
ALL_SCRIPTS := $(notdir $(wildcard $(HOMELAB_DIR)/scripts/*.sh))
BIN_SCRIPTS := $(filter-out $(SBIN_SCRIPTS),$(ALL_SCRIPTS))

BIN_FILES  := $(addprefix $(INSTALL_PATH)/,$(BIN_SCRIPTS))
SBIN_FILES := $(addprefix $(INSTALL_SBIN_PATH)/,$(SBIN_SCRIPTS))

.PHONY: install-all uninstall-all

install-all: assert-sanity $(BIN_FILES) $(SBIN_FILES)

uninstall-all:
	@for s in $(BIN_SCRIPTS); do \
		$(call uninstall_script,$$s); \
	done
	@for s in $(SBIN_SCRIPTS); do \
		@$(run_as_root) rm -f $(INSTALL_SBIN_PATH)/$$s; \
	done

# --------------------------------------------------------------------
# Homelab environment configuration
# --------------------------------------------------------------------

HOMELAB_ENV_SRC  := $(HOMELAB_DIR)/config/homelab.env
HOMELAB_ENV_DST  := /volume1/homelab/homelab.env

$(HOMELAB_ENV_DST): ensure-run-as-root $(HOMELAB_ENV_SRC)
	@$(run_as_root) install -D -m 0600 \
		$(HOMELAB_ENV_SRC) \
		$(HOMELAB_ENV_DST)
	@echo "🔐 homelab.env installed → $(HOMELAB_ENV_DST)"