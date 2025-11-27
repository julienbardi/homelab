# mk/01_common.mk
# Shared defaults and helper macros (safe to override with ?=)
INSTALL_PATH ?= /usr/local/bin
OWNER ?= root
GROUP ?= root
MODE ?= 0755

# run_as_root(command). Privilege guard with id -u (0 if root) evaluated at runtime not at parse time ---
#run_as_root = bash -c "if [ \"\$(id -u)\" -eq 0 ]; then eval \"\$1\"; else sudo bash -c \"\$1\"; fi" -- $(1)
#run_as_root = bash -c 'if [ "$$(id -u)" -eq 0 ]; then exec "$@"; else exec sudo bash -c '"'"'"$@"'"'"'; fi' -- $(1)
run_as_root = bash -c 'if [ "$$(id -u)" -eq 0 ]; then bash -c "$$1"; else sudo bash -c "$$1"; fi' -- '$(1)'

# install_script(src, name)
define install_script
	@bin/run-as-root install -o $(OWNER) -g $(GROUP) -m $(MODE) $(1) $(INSTALL_PATH)/$(2)
endef

# uninstall_script(name)
define uninstall_script
	@bin/run-as-root rm -f $(INSTALL_PATH)/$(1)
endef

# apt_install(tool, pkg-list)
# - $(1) is the command to check (e.g. curl)
# - $(2) is the apt package(s) to install (e.g. curl)
define apt_install
	@if ! command -v $(1) >/dev/null 2>&1; then \
		echo "[make] $(1) not found, installing: $(2)"; \
		$(call run_as_root,apt-get update && apt-get install -y --no-install-recommends $(2)); \
	else \
		VER_STR=$$( { $(1) --version 2>&1 || $(1) version 2>&1 || $(1) -v 2>&1; } | head -n1 ); \
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
		# original (fragile) wrapper commented out:
		# printf '%s\n' "DEBIAN_FRONTEND=noninteractive apt-get remove -y -o Dpkg::Options::=--force-confold $(1)" | bash -c "if [ \"\$(id -u)\" -eq 0 ]; then bash -s; else sudo bash -s; fi" || echo "[make] apt-get remove returned non-zero"; \
		# use direct sudo invocation to avoid nested quoting issues:
		DEBIAN_FRONTEND=noninteractive sudo apt-get remove -y -o Dpkg::Options::=--force-confold $(1) || echo "[make] apt-get remove returned non-zero"; \
		# original (fragile) autoremove wrapper commented out:
		# printf '%s\n' "DEBIAN_FRONTEND=noninteractive apt-get autoremove -y" | bash -c "if [ \"\$(id -u)\" -eq 0 ]; then bash -s; else sudo bash -s; fi" || true; \
		DEBIAN_FRONTEND=noninteractive sudo apt-get autoremove -y || true; \
		# stamp handling commented out for now (re-enable after fixing quoting)
		# if [ -n "$(2)" ]; then \
		#   printf '%s\n' "apt-mark unhold $(1) || true" | bash -c "if [ \"\$(id -u)\" -eq 0 ]; then bash -s; else sudo bash -s; fi"; \
		#   if [ -f "$(2)" ]; then \
		#       printf '%s\n' "rm -f $(2)" | bash -c "if [ \"\$(id -u)\" -eq 0 ]; then bash -s; else sudo bash -s; fi"; \
		#       echo "[make] Removed stamp $(2)"; \
		#       stampdir=$$(dirname "$(2)"); \
		#       if [ -d "$$stampdir" ] && [ -z "$$(ls -A "$$stampdir")" ]; then \
		#           printf '%s\n' "rmdir \"$$stampdir\" 2>/dev/null" | bash -c "if [ \"\$(id -u)\" -eq 0 ]; then bash -s; else sudo bash -s; fi" && echo "[make] Removed empty stamp dir $$stampdir" || true; \
		#       fi; \
		#   else \
		#       echo "[make] Stamp $(2) not present"; \
		#   fi; \
		# fi; \
	else \
		echo "[make] $(1) not installed; nothing to do"; \
	fi
endef


define remove_cmd
	@echo "[make] Removing $(1)..."
	@$(call run_as_root,$(2))
	@$(MAKE) autoremove
endef

.PHONY: autoremove
autoremove:
	@echo "[make] Cleaning up unused dependencies..."
	$(call run_as_root,apt-get autoremove -y)

# pattern rule: install scripts/<name>.sh -> $(INSTALL_PATH)/<name>
$(INSTALL_PATH)/%: scripts/%.sh
	$(call install_script,$<,$*)