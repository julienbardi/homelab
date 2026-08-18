# ------------------------------------------------------------
# 10_stamps.mk
# Deterministic, Centralized, Metadata-Aware Stamp System
# ------------------------------------------------------------
ifndef STAMP_DIR_ROOT
$(error STAMP_DIR_ROOT is not defined. It must be defined in config.mk)
endif

# ------------------------------------------------------------
# 1. Stamp Path Derivation
# ------------------------------------------------------------
# $(call STAMP_PATH_FROM_KEY,KEY_STRING)
define STAMP_PATH_FROM_KEY
$(if $(strip $(STAMP_DIR_ROOT)),,$(error STAMP_DIR_ROOT is not set when evaluating stamp key '$(1)'))\
$(if $(strip $(1)),,$(error Stamp key cannot be empty))\
$(STAMP_DIR_ROOT)/$(1).stamp
endef

# Backward compatibility alias
STAMP_PATH_FROM_FILE = $(call STAMP_PATH_FROM_KEY,$(1))

# ------------------------------------------------------------
# 2. Stamp Validation & Writing Macros
# ------------------------------------------------------------

# $(call STAMP_CHECK_MATCH,STAMP_PATH,VERSION,KEY_OR_FILE)
define STAMP_CHECK_MATCH
	[ -f "$(1)" ] && [ ! -L "$(1)" ] && \
	[ "$$(grep '^version=' "$(1)" 2>/dev/null | cut -d= -f2- || echo "")" = "$(2)" ] && \
	{ \
		if [ -e "$(3)" ]; then \
			_EX_SHA="$$(sha256sum "$(3)" 2>/dev/null | awk '{print $$$$1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")"; \
			_S_SHA="$$(grep '^sha256=' "$(1)" 2>/dev/null | cut -d= -f2- || echo "")"; \
			[ "$$_S_SHA" = "$$_EX_SHA" ]; \
		else \
			true; \
		fi; \
	}
endef

# $(call STAMP_WRITE_RECORD,STAMP_PATH,VERSION,KEY_OR_FILE)
define STAMP_WRITE_RECORD
	_DIR="$$(dirname "$(1)")"; \
	mkdir -p "$$_DIR"; \
	if [ -e "$(3)" ]; then \
		_SHA="$$(sha256sum "$(3)" 2>/dev/null | awk '{print $$$$1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")"; \
		_TYPE="regular"; \
		_OWNER="$$(stat -c '%U' "$(3)" 2>/dev/null || echo "root")"; \
		_GROUP="$$(stat -c '%G' "$(3)" 2>/dev/null || echo "root")"; \
		_PERM="$$(stat -c '%a' "$(3)" 2>/dev/null || echo "0644")"; \
	else \
		_SHA="$$(printf '%s' '$(3)' | sha256sum | awk '{print $$$$1}')"; \
		_TYPE="probe"; \
		_OWNER="root"; \
		_GROUP="root"; \
		_PERM="0644"; \
	fi; \
	_TMP="$(1).tmp"; \
	{ \
		echo "version=$(2)"; \
		echo "sha256=$$_SHA"; \
		echo "owner=$$_OWNER"; \
		echo "group=$$_GROUP"; \
		echo "perm=$$_PERM"; \
		echo "type=$$_TYPE"; \
	} > "$$_TMP"; \
	mv -f "$$_TMP" "$(1)"
endef

# ------------------------------------------------------------
# 3. Probe Integration Macro
# ------------------------------------------------------------

# STAMPED_PROBE(TARGET, SHELL_COMMAND, VERSION)
define STAMPED_PROBE
$(strip $(1)):
	@STAMP_PATH="$(call STAMP_PATH_FROM_KEY,$(strip $(1)))"; \
	TARGET_PATH="$(strip $(1))"; \
	VERSION="$(3)"; \
	_match=0; \
	if [ -f "$$STAMP_PATH" ] && [ ! -L "$$STAMP_PATH" ]; then \
		_s_ver="$$(grep '^version=' "$$STAMP_PATH" 2>/dev/null | cut -d= -f2- || echo "")"; \
		if [ "$$_s_ver" = "$$VERSION" ]; then \
			if [ -e "$$TARGET_PATH" ]; then \
				_ex_sha="$$(sha256sum "$$TARGET_PATH" 2>/dev/null | awk '{print $$1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")"; \
				_s_sha="$$(grep '^sha256=' "$$STAMP_PATH" 2>/dev/null | cut -d= -f2- || echo "")"; \
				[ "$$_s_sha" = "$$_ex_sha" ] && _match=1; \
			else \
				_match=1; \
			fi; \
		fi; \
	fi; \
	if [ "$$_match" -eq 1 ]; then \
		echo "⏩ $(strip $(1)) unchanged (fast-path OK)"; \
		exit 0; \
	fi; \
	echo "🔍 Running probe $(strip $(1))..."; \
	$(2) || { echo "❌ $(strip $(1)) failed"; exit 1; }; \
	_dir="$$(dirname "$$STAMP_PATH")"; \
	mkdir -p "$$_dir"; \
	if [ -e "$$TARGET_PATH" ]; then \
		_sha="$$(sha256sum "$$TARGET_PATH" 2>/dev/null | awk '{print $$1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")"; \
		_type="regular"; \
		_owner="$$(stat -c '%U' "$$TARGET_PATH" 2>/dev/null || echo "root")"; \
		_group="$$(stat -c '%G' "$$TARGET_PATH" 2>/dev/null || echo "root")"; \
		_perm="$$(stat -c '%a' "$$TARGET_PATH" 2>/dev/null || echo "0644")"; \
	else \
		_sha="$$(printf '%s' '$$TARGET_PATH' | sha256sum | awk '{print $$1}')"; \
		_type="probe"; \
		_owner="root"; \
		_group="root"; \
		_perm="0644"; \
	fi; \
	_tmp="$$STAMP_PATH.tmp"; \
	{ \
		echo "version=$$VERSION"; \
		echo "sha256=$$_sha"; \
		echo "owner=$$_owner"; \
		echo "group=$$_group"; \
		echo "perm=$$_perm"; \
		echo "type=$$_type"; \
	} > "$$_tmp"; \
	mv -f "$$_tmp" "$$STAMP_PATH"; \
	echo "✅ $(strip $(1)) complete"
endef