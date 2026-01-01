# --------------------------------------------------------------------
# mk/01_common.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Defines run_as_root := ./bin/run-as-root
# - All recipes must call $(run_as_root) with argv tokens.
# - Do not wrap entire command in quotes.
# - Escape operators (\>, \|, \&\&, \|\|) so they survive Make parsing.
# --------------------------------------------------------------------
# Repo root (overrideable by top-level Makefile / environment)
HOMELAB_DIR ?= $(CURDIR)

# Fallback for recursive make (do not force; let make set it if present)
MAKE ?= $(MAKE)

run_as_root := $(HOMELAB_DIR)/bin/run-as-root

INSTALL_PATH ?= /usr/local/bin
OWNER ?= root
GROUP ?= root
MODE ?= 0755

# Stamp dir (overrideable)
STAMP_DIR ?= /var/lib/homelab

# log(message). Show on screen and write to syslog/journald
define log
echo "$1" >&2; command -v logger >/dev/null 2>&1 && logger -t homelab-make "$1"
endef

# Ensure run_as_root helper exists and is executable (warn, do not fail)
ifeq ($(shell test -x $(run_as_root) >/dev/null 2>&1 && echo ok || echo no),no)
$(warning "Warning: $(run_as_root) not found or not executable. Some targets may fail.")
endif

# install_script(src, name)
define install_script
	@$(run_as_root) install -o $(OWNER) -g $(GROUP) -m $(MODE) $(1) $(INSTALL_PATH)/$(2)
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
APT_UPDATE_MAX_AGE ?= 21600   # 6 hours in seconds

define apt_update_if_needed
	@$(run_as_root) mkdir -p --mode=0755 $(STAMP_DIR) >/dev/null 2>&1 || true; \
	if [ ! -f "$(APT_UPDATE_STAMP)" ] || [ $$(expr $$(date +%s) - $$(stat -c %Y "$(APT_UPDATE_STAMP)" 2>/dev/null || echo 0) ) -gt $(APT_UPDATE_MAX_AGE) ]; then \
		echo "[make] Running apt-get update (stamp missing or older than $(APT_UPDATE_MAX_AGE)s)"; \
		$(run_as_root) apt-get update; \
		$(run_as_root) sh -c 'mkdir -p "$(STAMP_DIR)" && date +%s > "$(APT_UPDATE_STAMP)"'; \
	else \
		echo "[make] apt-get update stamp is recent; skipping apt-get update"; \
	fi
endef

.PHONY: apt-update
apt-update:
	@$(call apt_update_if_needed)

# apt_install(tool, pkg-list)
# - $(1) is the command to check (e.g. curl)
# - $(2) is the apt package(s) to install (e.g. curl)
define apt_install
	@if ! command -v $(1) >/dev/null 2>&1; then \
		echo "[make] $(1) not found, installing: $(2)"; \
		$(call apt_update_if_needed); \
		$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confold $(2); \
	else \
		VER_STR=$$( \
  			if [ "$(1)" = "strace" ]; then \
				strace -V 2>&1 | head -n1; \
			elif [ "$(1)" = "vnstat" ]; then \
				vnstat --version 2>&1 | head -n1; \
			else \
    			{ $(1) --version 2>&1 || $(1) version 2>&1 || $(1) -v 2>&1 || echo "unknown"; } | head -n1; \
  			fi \
		);
		echo "$$(date '+%Y-%m-%d %H:%M:%S') [make] $(1) version: $$VER_STR"; \
	fi
endef

# Usage:
#   $(call apt_remove,packagename)                     -> remove package if present
#   $(call apt_remove,packagename,/path/to/stamp.file) -> remove package and remove stamp; also apt-mark unhold
define apt_remove
	@echo "[make] Requested removal of $(1)..."; \
	if dpkg -s $(1) >/dev/null 2>&1; then \
		echo "[make] $(1) is installed; removing..."; \
		$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get remove -y -o Dpkg::Options::=--force-confold $(1) || echo "[make] apt-get remove returned non-zero"; \
		if [ -n "$(2)" ]; then \
			$(run_as_root) apt-mark unhold $(1) >/dev/null 2>&1 || true; \
			$(run_as_root) rm -f $(2) >/dev/null 2>&1 || true; \
		fi; \
	else \
		echo "[make] $(1) not installed; nothing to do"; \
	fi
endef

define remove_cmd
	@echo "[make] Removing $(1)..."
	@$(run_as_root) sh -c '$(2)'
endef

.PHONY: homelab-cleanup-deps
homelab-cleanup-deps: ; # clear any built-in recipe
	@echo "[make] Cleaning up unused dependencies..."
	@$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true

# simple prereq check target (useful in CI)
.PHONY: check-prereqs
check-prereqs:
	@echo "[make] Checking required commands..."; \
	for cmd in sudo apt-get curl git ip wg awk sort mktemp; do \
		command -v $$cmd >/dev/null 2>&1 || { echo "[make] Missing required command: $$cmd"; exit 1; }; \
	done; \
	echo "[make] All required commands present"

# pattern rule: install scripts/<name>.sh -> $(INSTALL_PATH)/<name>
$(INSTALL_PATH)/%: $(HOMELAB_DIR)/scripts/%.sh
	$(call install_script,$<,$*)
