# --------------------------------------------------------------------
# mk/01_common.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Defines run_as_root := ./bin/run-as-root
# - All recipes must call $(run_as_root) with argv tokens.
# - Do not wrap entire command in quotes.
# - Escape operators (\>, \|, \&\&, \|\|) so they survive Make parsing.
# --------------------------------------------------------------------
run_as_root := ./bin/run-as-root

INSTALL_PATH ?= /usr/local/bin
OWNER ?= root
GROUP ?= root
MODE ?= 0755

# log(message). Show on screen and write to syslog/journald
define log
echo "$1" >&2; command -v logger >/dev/null 2>&1 && logger -t homelab-make "$1"
endef

# install_script(src, name)
define install_script
	@$(run_as_root) install -o $(OWNER) -g $(GROUP) -m $(MODE) $(1) $(INSTALL_PATH)/$(2)
endef

# uninstall_script(name)
define uninstall_script
	@$(run_as_root) rm -f $(INSTALL_PATH)/$(1)
endef

# apt_install(tool, pkg-list)
# - $(1) is the command to check (e.g. curl)
# - $(2) is the apt package(s) to install (e.g. curl)
define apt_install
	@if ! command -v $(1) >/dev/null 2>&1; then \
		echo "[make] $(1) not found, installing: $(2)"; \
		$(run_as_root) apt-get update; \
		$(run_as_root) apt-get install -y --no-install-recommends $(2); \
	else \
		VER_STR=$$( \
		if $(1) -v >/dev/null 2>&1; then \
			$(1) -v 2>&1 | head -n1; \
		elif $(1) --version >/dev/null 2>&1; then \
			$(1) --version 2>&1 | head -n1; \
		elif $(1) version >/dev/null 2>&1; then \
			$(1) version 2>&1 | head -n1; \
		else \
			echo "unknown"; \
		fi ); \
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
		DEBIAN_FRONTEND=noninteractive $(run_as_root) apt-get remove -y -o Dpkg::Options::=--force-confold $(1) || echo "[make] apt-get remove returned non-zero"; \
	else \
		echo "[make] $(1) not installed; nothing to do"; \
	fi
endef

define remove_cmd
	@echo "[make] Removing $(1)..."
	@$(run_as_root) sh -c '$(2)'
endef

.PHONY: homelab-cleanup‑deps
homelab-cleanup‑deps: ; # clear any built‑in recipe
	@echo "[make] Cleaning up unused dependencies..."
	@DEBIAN_FRONTEND=noninteractive $(run_as_root) apt-get autoremove -y || true

# pattern rule: install scripts/<name>.sh -> $(INSTALL_PATH)/<name>
$(INSTALL_PATH)/%: scripts/%.sh
	$(call install_script,$<,$*)
