# ------------------------------------------------------------
# mk/10_stamps_prompt.mk
# Centralized prompt for generating the perfect 20_stamps.mk
# ------------------------------------------------------------

define PERFECT_STAMP_PROMPT
Generate a complete 20_stamps.mk file implementing a deterministic, centralized, metadata-aware stamp system for my homelab.

Requirements:

## 1. Centralized Stamp Storage
- All stamps must be stored under $$(STAMP_DIR_ROOT).
- Stamp filenames must be derived from the target file/directory path using a Kopia-style “2+3” hashing approach:
    • Compute SHA256 of the *path string*
    • Encode it as <first2>/<next3>/<fullhash>.stamp
- Provide a macro STAMP_PATH_FROM_FILE(FILE_PATH) that returns the full stamp path under $$(STAMP_DIR_ROOT).

## 2. Unified Stamp Format
Every stamp file must contain exactly these fields, one per line:
version=<VERSION or empty>
sha256=<SHA256 of FILE_PATH or probe result>
owner=<OWNER name>
group=<GROUP name>
perm=<OCTAL permissions>
type=<regular|symlink>

- Version must be optional.
- SHA256 must be deterministic.
- Owner/group/perm/type must reflect the actual installed artifact.
- No timestamps.
- No mktemp randomness.
- No multi-field single-line formats.

## 3. Unified Stamp Macros
Provide these macros:

### 3.1 STAMP_WRITE(STAMP_PATH, VERSION, FILE_PATH)
- Automatically creates the nested parent directories (mkdir -p) for STAMP_PATH
- Computes SHA256 of FILE_PATH (or falls back to a deterministic string key if FILE_PATH is a logical target)
- Detects owner, group, permissions, and file type
- Writes the unified stamp format
- Installs the stamp with owner=root, group=root, perm=0644
- Must be Make-safe (double $$ everywhere)
- Must not use mktemp randomness
- Must not embed timestamps

### 3.2 STAMP_FASTPATH(STAMP_PATH, VERSION, FILE_PATH)
- Reads the existing stamp
- Validates:
    • version matches
    • sha256 matches
    • owner matches
    • group matches
    • perm matches
    • type matches
- If all match, prints a fast-path message and exits 0
- Otherwise, exits non-zero
- Must be Make-safe

### 3.3 STAMP_VALIDATE(STAMP_PATH)
- Validates that the stamp file is well-formed
- Ensures all required fields exist
- Ensures no malformed lines

### 3.4 STAMP_READ_FIELD(STAMP_PATH, FIELD)
- Returns the value of a field (e.g., version, sha256, owner, group, perm, type)

## 4. Probe Integration
Provide a macro:

### STAMPED_PROBE(TARGET, PROBE_MACRO, FILE_PATH, VERSION)
- Computes stamp path using STAMP_PATH_FROM_FILE(FILE_PATH)
- Runs fast-path via STAMP_FASTPATH
- If fast-path succeeds, skip probe
- Otherwise:
    • run probe macro (defined via define/endef, not passed via $$(call ...))
    • write stamp via STAMP_WRITE
- Must be Make-safe
- Must not expand multi-line probe bodies via $$(call ...)

## 5. Make-Safety Requirements
- All macros must escape $$ correctly
- No multi-line bodies passed through $$(call ...)
- All probe bodies must be defined via define/endef and invoked directly
- No brace corruption
- No unexpected EOF
- No collapsing of newlines

## 6. Output Format
- Produce a complete 20_stamps.mk file
- Include comments explaining each macro
- Include examples of usage
- Must be ready to paste directly into my homelab repo
- Must not require external tools beyond POSIX shell and GNU Make

## 7. Performance Requirements
- Fast-path must be O(1)
- No unnecessary shelling out
- No scanning directories
- No recomputing SHA256 unless needed

## 8. Determinism Requirements
- No timestamps
- No mktemp randomness
- No non-deterministic content
- No environment-dependent behavior

Generate the full 20_stamps.mk file now.
endef

# To print the prompt:
print-stamp-prompt:
	@printf "%s\n" "$$(PERFECT_STAMP_PROMPT)"

# ------------------------------------------------------------
# 10_stamps.mk
# Deterministic, Centralized, Metadata-Aware Stamp System
# ------------------------------------------------------------

STAMP_DIR_ROOT ?= /tank/julie/src/homelab/.state/stamps
_SAFE_STAMP_ROOT := $(patsubst %/,%,$(STAMP_DIR_ROOT))

# ------------------------------------------------------------
# 1. Stamp Path Derivation (Kopia-style "2+3" hashing)
# ------------------------------------------------------------
# $(call STAMP_PATH_FROM_FILE,FILE_PATH)
define STAMP_PATH_FROM_FILE
$(shell _H="$$(printf '%s' '$(1)' | sha256sum | awk '{print $$$$1}')"; echo "$(_SAFE_STAMP_ROOT)/$$(echo "$$_H" | cut -c1-2)/$$(echo "$$_H" | cut -c3-5)/$$_H.stamp")
endef

# ------------------------------------------------------------
# 2. Stamp Field Reader & Validator
# ------------------------------------------------------------
# $(call STAMP_READ_FIELD,STAMP_PATH,FIELD)
define STAMP_READ_FIELD
$(shell grep '^$(2)=' "$(1)" 2>/dev/null | cut -d= -f2- || echo "")
endef

# $(call STAMP_VALIDATE,STAMP_PATH)
define STAMP_VALIDATE
	if [ ! -f "$(1)" ] || [ -L "$(1)" ]; then \
		exit 1; \
	fi; \
	for _F in sha256 owner group perm type; do \
		if ! grep -q "^$$_F=" "$(1)"; then \
			exit 1; \
		fi; \
	done
endef

# ------------------------------------------------------------
# 3. Unified Stamp Macros
# ------------------------------------------------------------

# 3.1 STAMP_WRITE(STAMP_PATH, VERSION, FILE_PATH)
define STAMP_WRITE
	_DIR="$$(dirname "$(1)")"; \
	$(run_as_root) mkdir -p "$$_DIR"; \
	if [ -e "$(3)" ]; then \
		_SHA="$$(sha256sum "$(3)" 2>/dev/null | awk '{print $$$$1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")"; \
		if [ -L "$(3)" ]; then _TYPE="symlink"; else _TYPE="regular"; fi; \
		_OWNER="$$(stat -c '%U' "$(3)" 2>/dev/null || stat -f '%Su' "$(3)" 2>/dev/null || echo "root")"; \
		_GROUP="$$(stat -c '%G' "$(3)" 2>/dev/null || stat -f '%Sg' "$(3)" 2>/dev/null || echo "root")"; \
		_RAW_PERM="$$(stat -c '%a' "$(3)" 2>/dev/null || stat -f '%p' "$(3)" | tail -c 5 || echo "0644")"; \
		_PERM="$$(printf "%04d" "$$_RAW_PERM" 2>/dev/null || echo "0644")"; \
	else \
		_SHA="$$(printf '%s' '$(3)' | sha256sum | awk '{print $$$$1}')"; \
		_TYPE="regular"; \
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
	$(run_as_root) install -m 0644 -o root -g root "$$_TMP" "$(1)"; \
	rm -f "$$_TMP"
endef

# 3.2 STAMP_FASTPATH(STAMP_PATH, VERSION, FILE_PATH)
define STAMP_FASTPATH
	if [ -f "$(1)" ] && [ ! -L "$(1)" ]; then \
		_EX_VER="$(2)"; \
		if [ -e "$(3)" ]; then \
			_EX_SHA="$$(sha256sum "$(3)" 2>/dev/null | awk '{print $$$$1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")"; \
			if [ -L "$(3)" ]; then _EX_TYPE="symlink"; else _EX_TYPE="regular"; fi; \
			_EX_OWNER="$$(stat -c '%U' "$(3)" 2>/dev/null || stat -f '%Su' "$(3)" 2>/dev/null || echo "root")"; \
			_EX_GROUP="$$(stat -c '%G' "$(3)" 2>/dev/null || stat -f '%Sg' "$(3)" 2>/dev/null || echo "root")"; \
			_RAW_P="$$(stat -c '%a' "$(3)" 2>/dev/null || stat -f '%p' "$(3)" | tail -c 5 || echo "0644")"; \
			_EX_PERM="$$(printf "%04d" "$$_RAW_P" 2>/dev/null || echo "0644")"; \
		else \
			_EX_SHA="$$(printf '%s' '$(3)' | sha256sum | awk '{print $$$$1}')"; \
			_EX_TYPE="regular"; \
			_EX_OWNER="root"; \
			_EX_GROUP="root"; \
			_EX_PERM="0644"; \
		fi; \
		_S_VER="$$(grep '^version=' "$(1)" | cut -d= -f2- || echo "")"; \
		_S_SHA="$$(grep '^sha256=' "$(1)" | cut -d= -f2- || echo "")"; \
		_S_OWNER="$$(grep '^owner=' "$(1)" | cut -d= -f2- || echo "")"; \
		_S_GROUP="$$(grep '^group=' "$(1)" | cut -d= -f2- || echo "")"; \
		_S_PERM="$$(grep '^perm=' "$(1)" | cut -d= -f2- || echo "")"; \
		_S_TYPE="$$(grep '^type=' "$(1)" | cut -d= -f2- || echo "")"; \
		if [ "$$_S_VER" = "$$_EX_VER" ] && [ "$$_S_SHA" = "$$_EX_SHA" ] && [ "$$_S_OWNER" = "$$_EX_OWNER" ] && [ "$$_S_GROUP" = "$$_EX_GROUP" ] && [ "$$_S_PERM" = "$$_EX_PERM" ] && [ "$$_S_TYPE" = "$$_EX_TYPE" ]; then \
			exit 0; \
		fi; \
	fi; \
	exit 1
endef

# ------------------------------------------------------------
# 4. Probe Integration Macro
# ------------------------------------------------------------

# STAMPED_PROBE(TARGET, PROBE_MACRO, FILE_PATH, VERSION)
define STAMPED_PROBE
$(1): $(3)
	@_STAMP_PATH="$(call STAMP_PATH_FROM_FILE,$(3))"; \
	if $(call STAMP_FASTPATH,$$(_STAMP_PATH),$(4),$(3)); then \
		echo "⏩ $(1) unchanged (fast-path OK)"; \
		exit 0; \
	fi; \
	echo "🔍 Running probe $(1)..."; \
	$($(2)) || { echo "❌ $(1) failed"; exit 1; }; \
	$(call STAMP_WRITE,$$(_STAMP_PATH),$(4),$(3)); \
	echo "✅ $(1) complete"
endef