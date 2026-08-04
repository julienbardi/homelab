# ====================================================================
# mk/common/core.mk — Operator Primitives
# ====================================================================
# CONTRACT:
# - Defines run_as_root := /usr/local/sbin/run-as-root.sh
# - Any recipe invoking $(run_as_root) MUST declare:
#       <target>: | $(run_as_root)
#   to guarantee the wrapper exists before execution.
# - All privileged mutations MUST pass through run-as-root.
# ====================================================================


# --------------------------------------------------------------------
# Stamp Directories (root + user)
# --------------------------------------------------------------------
.PHONY: ensure-stamps
ensure-stamps:
	@{ \
	# --- ROOT STAMP --- \
	if [ ! -d "$(STAMP_DIR_ROOT)" ]; then \
		echo "📁 Creating STAMP_DIR_ROOT: $(STAMP_DIR_ROOT)"; \
		$(run_as_root) install -d -m 0755 -o $(ROOT_UID) -g $(ROOT_GID) "$(STAMP_DIR_ROOT)"; \
	else \
		$(run_as_root) chown "$(ROOT_UID):$(ROOT_GID)" "$(STAMP_DIR_ROOT)"; \
		$(run_as_root) chmod 0755 "$(STAMP_DIR_ROOT)"; \
	fi; \
	\
	# --- USER STAMP --- \
	if [ ! -d "$(STAMP_DIR_USER)" ]; then \
		echo "📁 Creating STAMP_DIR_USER: $(STAMP_DIR_USER)"; \
		$(run_as_root) install -d -m 0700 -o "$$(id -u)" -g "$$(id -g)" "$(STAMP_DIR_USER)"; \
	else \
		$(run_as_root) chown ""$$(id -u)":"$$(id -g)"" "$(STAMP_DIR_USER)"; \
		$(run_as_root) chmod 700 "$(STAMP_DIR_USER)"; \
	fi; \
	}

.PHONY: ensure-stamps-v1
ensure-stamps-v1: ensure-stamp-user ensure-stamp-root

.PHONY: ensure-stamp-user
ensure-stamp-user:
	@mkdir -p "$(STAMP_DIR_USER)"; \
	$(run_as_root) chown "$$(id -u):$$(id -g)" "$(STAMP_DIR_USER)"; \
	$(run_as_root) chmod 0700 "$(STAMP_DIR_USER)"

.PHONY: ensure-stamp-root
ensure-stamp-root:
	@$(run_as_root) mkdir -p "$(STAMP_DIR_ROOT)"; \
	$(run_as_root) chown "$(ROOT_UID):$(ROOT_GID)" "$(STAMP_DIR_ROOT)"; \
	$(run_as_root) chmod 0755 "$(STAMP_DIR_ROOT)"

# --------------------------------------------------------------------
# Bootstrap: Privilege Wrapper + IFC Engines
# --------------------------------------------------------------------

# 1. Privilege Boundary
$(run_as_root): $(RUN_ROOT_SRC)
	@echo "🚀 Bootstrapping $(run_as_root) ..."
	@sudo mkdir -p $(INSTALL_SBIN_PATH)
	@sudo install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 "$<" "$@"

# 2. IFC v3 (single-file engine)
$(INSTALL_FILE_IF_CHANGED): $(IFC_V3_SINGLE_SRC)
	@echo "🚀 Bootstrapping $(INSTALL_FILE_IF_CHANGED) ..."
	@sudo mkdir -p $(INSTALL_PATH)
	@sudo install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 "$<" "$@"

# 3. IFC v3 (vector engine)
$(INSTALL_FILES_IF_CHANGED): $(IFC_V3_PLURAL_SRC) | $(INSTALL_FILE_IF_CHANGED_V3)
	@echo "🚀 Bootstrapping $(INSTALL_FILES_IF_CHANGED) ..."
	@sudo install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 "$<" "$@"


# --------------------------------------------------------------------
# IFC Bootstrap Dependency Group
# --------------------------------------------------------------------
BOOTSTRAP_CORE := \
	$(run_as_root) \
	$(INSTALL_FILE_IF_CHANGED) \
	$(INSTALL_FILES_IF_CHANGED)

# --------------------------------------------------------------------
# URL-based IFC Engine
# --------------------------------------------------------------------
$(INSTALL_URL_FILE_IF_CHANGED): $(IFC_URL_SRC) | $(BOOTSTRAP_CORE)
	@$(call install_file,$<,$@,$(ROOT_UID),$(ROOT_GID),0755)

# --------------------------------------------------------------------
# IFC Macro: install_file (strict numeric wrapper)
# --------------------------------------------------------------------
define install_file
	rc=0; \
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) \
		"" "" "$(1)" \
		"" "" "$(2)" \
		"$(3)" "$(4)" "$(5)" \
		|| rc=$$?; \
	\
	case "$$rc" in \
		0) ;; \
		3) echo "📝 Updated: $(2)" ;; \
		''|*[!0-9]*) ;; \
		*) echo "❌ IFC: Fatal error (exit $$rc) installing $(2)" >&2; exit "$$rc" ;; \
	esac
endef
