# ============================================================
# mk/99_lint.mk — lint orchestration
# ============================================================
# CONTRACT:
# - lint targets never mutate system state
# - install-* targets must either:
#   - have a corresponding verify-* target, or
#   - perform an explicit sentinel check
# - apt_install must not appear without post-install verification
# - lint-ci enforces all semantic invariants

# Tools (allow override)
SHELLCHECK ?= shellcheck
SHELLCHECK_OPTS ?= -s bash -x --external-sources --source-path=$(MAKEFILE_DIR)
CODESPELL ?= codespell
ASPELL ?= aspell
CHECKMAKE ?= checkmake

# Files to lint
# Prefer git-tracked files; fallback to find for non-git contexts
SH_FILES := $(shell git -C $(MAKEFILE_DIR) ls-files '*.sh' 2>/dev/null || true)
ifeq ($(strip $(SH_FILES)),)
SH_FILES := $(shell find $(MAKEFILE_DIR) -type f -name '*.sh' -print)
endif

# Exclude archived scripts from linting
SH_FILES := $(filter-out archive/%,$(SH_FILES))


MK_FILES := $(shell git -C $(MAKEFILE_DIR) ls-files 'mk/*.mk' 2>/dev/null || true)
ifeq ($(strip $(MK_FILES)),)
MK_FILES := $(wildcard $(MAKEFILE_DIR)/mk/*.mk)
endif

MAKEFILES := $(MAKEFILE_DIR)/Makefile $(MK_FILES)

define require_tool
@if ! command -v $(1) >/dev/null 2>&1; then \
	echo "[lint] ERROR: $(1) not installed"; exit 2; \
fi
endef

.PHONY: lint-semantic lint-semantic-strict
lint-semantic:
	@echo "[lint] Checking semantic invariants (permissive)..."
	@bad=$$(grep -R "^[[:space:]]*install-pkg-" mk/*.mk \
	    | sed 's/:.*//' | sort -u \
	    | while read f; do \
	        grep -q "verify-pkg-" "$$f" || echo "$$f"; \
	      done); \
	if [ -n "$$bad" ]; then \
	    echo "[lint] � ️ install targets without verify targets:"; \
	    echo "$$bad"; \
	fi

lint-semantic-strict:
	@echo "[lint-ci] Enforcing semantic invariants..."
	@bad=$$(grep -R "^[[:space:]]*install-pkg-" mk/*.mk \
	    | sed 's/:.*//' | sort -u \
	    | while read f; do \
	        grep -q "verify-pkg-" "$$f" || echo "$$f"; \
	      done); \
	if [ -n "$$bad" ]; then \
	    echo "[lint-ci] ERROR: install targets missing verification:"; \
	    echo "$$bad"; \
	    exit 1; \
	fi


.PHONY: lint lint-all lint-fast lint-ci lint-scripts-partial lint-scripts \
	    lint-shellcheck \
	    lint-shellcheck-strict \
	    lint-makefile lint-makefile-strict lint-headscale lint-spell lint-spell-strict

# Default lint target: permissive full suite
lint: lint-all

# Fast lint: shell syntax + shellcheck + checkmake (permissive)
lint-fast: lint-gitignore lint-scripts lint-makefile \
	check-control-plane-reasoning

# Full lint: fast + spell checks + headscale config test (permissive)
lint-all: lint-fast lint-spell lint-headscale

# Strict CI lint: fail on any issue (ShellCheck warnings, checkmake errors, codespell, aspell)
lint-ci: lint-shellcheck-strict lint-makefile-strict lint-spell-strict lint-headscale-strict lint-semantic-strict \
	check-control-plane-reasoning
	@echo "[lint-ci] All checks passed (strict mode)."

# Run shell syntax check and ShellCheck across all tracked .sh files (permissive)
lint-scripts-partial:
	@echo "[lint] Checking shell syntax for tracked .sh files..."
	@command -v bash >/dev/null 2>&1 || { \
	    echo "[lint] ERROR: bash not found (required for syntax check)"; exit 2; }
	@if [ -z "$(SH_FILES)" ]; then \
	    echo "[lint] No shell files found to lint"; \
	else \
	    rc=0; \
	    for f in $(SH_FILES); do \
	        [ -f "$$f" ] || { echo "[lint] Skipping missing file: $$f"; continue; }; \
	        echo "[lint] bash -n $$f"; \
	        bash -n "$$f" || { echo "[lint] Syntax error in $$f"; rc=1; }; \
	    done; \
	    exit $$rc; \
	fi

lint-scripts: lint-scripts-partial lint-shellcheck

# ShellCheck permissive: never fails the whole run (useful for local dev)
lint-shellcheck:
	@echo "[shellcheck] Scanning tracked shell files (permissive)"
	@if ! command -v $(SHELLCHECK) >/dev/null 2>&1; then \
	  echo "[shellcheck] shellcheck not installed; install with 'make deps' or set SHELLCHECK=..."; \
	else \
	  if [ -z "$(SH_FILES)" ]; then \
	    echo "[shellcheck] No shell files to check"; \
	  else \
	    for f in $(SH_FILES); do \
	      [ -f "$$f" ] || { echo "[shellcheck] Skipping missing file: $$f"; continue; }; \
	      echo "[shellcheck] $$f"; \
	      $(SHELLCHECK) $(SHELLCHECK_OPTS) "$$f" || true; \
	    done; \
	  fi; \
	fi

# ShellCheck strict: fail on any ShellCheck non-zero exit
lint-shellcheck-strict:
	@echo "[shellcheck] Scanning tracked shell files (strict)"
	$(call require_tool,$(SHELLCHECK))
	@if [ -z "$(SH_FILES)" ]; then \
	    echo "[shellcheck] No shell files to check"; \
	else \
	    rc=0; \
	    for f in $(SH_FILES); do \
	        [ -f "$$f" ] || { echo "[shellcheck] Skipping missing file: $$f"; continue; }; \
	        echo "[shellcheck] $$f"; \
	        $(SHELLCHECK) $(SHELLCHECK_OPTS) "$$f" || rc=$$?; \
	    done; \
	    if [ $$rc -ne 0 ]; then echo "[shellcheck] Errors/warnings detected"; exit $$rc; fi; \
	fi

# Spell checks: codespell (permissive) and aspell (permissive)
lint-spell:
	@echo "[lint] Running codespell and aspell (permissive)..."
	@echo "[lint] NOTE: checkmake warnings are advisory only"
	@if command -v $(CODESPELL) >/dev/null 2>&1; then \
	  echo "[codespell] scanning..."; \
	  $(CODESPELL) --skip="archive/*,*.png,*.jpg,*.jpeg,*.gif,*.svg,.git" \
	    $(SH_FILES) $(MAKEFILE_DIR) || true; \
	else \
	  echo "[lint] codespell not installed; skipping codespell"; \
	fi
	@if command -v $(ASPELL) >/dev/null 2>&1; then \
	  echo "[aspell] scanning comments (lightweight pass)"; \
	  (for f in $(SH_FILES) $(MAKEFILES); do \
	     [ -f "$$f" ] || continue; \
	     sed -n 's/^[[:space:]]*#//p' "$$f" | sed 's/[^[:alpha:][:space:]]/ /g'; \
	   done) | tr '[:upper:]' '[:lower:]' | tr -s ' ' '\n' | sort -u | $(ASPELL) list | sort -u || true; \
	else \
	  echo "[lint] aspell not installed; skipping aspell"; \
	fi

# Spell checks strict: fail if codespell or aspell find issues
lint-spell-strict:
	@echo "[lint-ci] Running codespell and aspell (strict)..."
	$(call require_tool,$(CODESPELL))
	$(call require_tool,$(ASPELL))

	@echo "[codespell] scanning..."
	@$(CODESPELL) --skip="*.png,*.jpg,*.jpeg,*.gif,*.svg" $(MAKEFILE_DIR)

	@echo "[aspell] scanning comments (strict)"
	@bad=$$( (for f in $(SH_FILES) $(MAKEFILES); do \
	    [ -f "$$f" ] || continue; \
	    sed -n 's/^[[:space:]]*#//p' "$$f" | sed 's/[^[:alpha:][:space:]]/ /g'; \
	done) | tr '[:upper:]' '[:lower:]' | tr -s ' ' '\n' | sort -u | $(ASPELL) list | sort -u ); \
	if [ -n "$$bad" ]; then \
	    echo "[aspell] Unknown words found:"; \
	    echo "$$bad"; \
	    exit 1; \
	fi

# Lint Makefiles and mk/*.mk using checkmake when available (permissive)
lint-makefile:
	@echo "[lint] Linting Makefiles and mk/*.mk (permissive)..."
	@echo "[lint] NOTE: checkmake warnings are advisory only"
	@if command -v $(CHECKMAKE) >/dev/null 2>&1; then \
	  for mf in $(MAKEFILE_DIR)Makefile $(MK_FILES); do \
	    [ -f "$$mf" ] || continue; \
	    echo "[checkmake] $$mf"; \
	    $(CHECKMAKE) "$$mf" 2>&1 \
	      | grep -v '^[[:space:]]*minphony' \
	      | grep -v '^[[:space:]]*"all"' \
	      | grep -v '^[[:space:]]*"clean"' \
	      | grep -v '^[[:space:]]*"test"' \
	      || true; \
	  done; \
	else \
	  echo "[lint] checkmake not installed; skipping Makefile lint"; \
	fi


# Lint Makefiles strict: fail on checkmake errors
lint-makefile-strict:
	@echo "[lint-ci] Linting Makefiles and mk/*.mk (strict)..."
	$(call require_tool,$(CHECKMAKE))
	@for mf in $(MAKEFILE_DIR)Makefile $(MK_FILES); do \
	    [ -f "$$mf" ] || continue; \
	    echo "[checkmake] $$mf"; \
	    $(CHECKMAKE) "$$mf" || { echo "[checkmake] Issues in $$mf"; exit 1; }; \
	done

# Headscale config test (use run_as_root helper)
lint-headscale: ensure-run-as-root
	@echo "[lint] Linting /etc/headscale/config.yaml (permissive)..."
	@if [ -z "$(run_as_root)" ]; then \
	  echo "[lint] run_as_root helper not defined; skipping headscale configtest"; \
	elif command -v headscale >/dev/null 2>&1; then \
	  $(run_as_root) headscale configtest --config /etc/headscale/config.yaml || echo "[lint] Headscale configtest failed (permissive)"; \
	else \
	  echo "[lint] headscale binary not found; skipping headscale configtest"; \
	fi

# Headscale config test strict
lint-headscale-strict: ensure-run-as-root
	@echo "[lint-ci] Linting /etc/headscale/config.yaml (strict)..."
	@if [ -z "$(run_as_root)" ]; then \
	  echo "[lint-ci] ERROR: run_as_root helper not defined"; exit 2; \
	elif ! command -v headscale >/dev/null 2>&1; then \
	  echo "[lint-ci] headscale binary not found; skipping headscale configtest"; \
	else \
	  $(run_as_root) headscale configtest --config /etc/headscale/config.yaml || { echo "[lint-ci] Headscale config invalid"; exit 1; }; \
	fi

.PHONY: check-control-plane-reasoning
check-control-plane-reasoning:
	@echo "[lint] Checking for forbidden intent-level semantic reasoning in router shell scripts..."
	@set -eu; \
	if rg -n --hidden --no-ignore-vcs \
	    -e '\|\s*uniq\s+-[cd]' \
	    -e 'sort\s*\|\s*uniq' \
	    -e 'awk.*(count|seen|found|dup|duplicate)' \
	    -e 'awk.*exit\(' \
	    scripts/; then \
	    echo "[lint] ERROR: intent-level semantic reasoning detected in router shell scripts"; \
	    exit 1; \
	else \
	    echo "[lint] OK: no forbidden semantic reasoning detected"; \
	fi


