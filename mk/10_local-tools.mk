# mk/10_local-tools.mk
# ------------------------------------------------------------
# LOCAL DEVELOPER TOOLING
# ------------------------------------------------------------
#
# Scope:
#   - Local machine only (NAS / workstation)
#   - MUST NOT touch router state
#
# Policy:
#   - Core tools are pinned and verified
#   - System tools are required, not vendored
#   - checkmake is best-effort only (non-reproducible)
# ------------------------------------------------------------

# ------------------------------------------------------------
# Local tool root
# ------------------------------------------------------------

SPELLCHECK_FILES := *.md
SPELLCHECK_MAKEFILES := Makefile mk/*.mk

# ------------------------------------------------------------
# Deterministic local tools
# ------------------------------------------------------------

YQ := $(TOOLS_DIR)/yq/yq

# ------------------------------------------------------------
# Optional dev tool (best-effort)
# ------------------------------------------------------------

CHECKMAKE := $(TOOLS_DIR)/checkmake

# ------------------------------------------------------------
# Tool bootstrap
# ------------------------------------------------------------

.PHONY: tools
tools: require-awk | $(YQ)

# --- yq (pinned, verified) ----------------------------------

$(TOOLS_DIR)/yq:
	@if [ -e "$@" ] && [ ! -d "$@" ]; then \
		echo "❌ $@ exists but is not a directory (removing poisoned state)"; \
		rm -f "$@"; \
	fi
	@mkdir -p "$@"

$(YQ): | $(TOOLS_DIR)/yq
	@curl -fsSL \
		https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 \
		-o $@.tmp
	@echo "a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7  $@.tmp" | sha256sum -c -
	@chmod +x $@.tmp
	@mv $@.tmp $@

# ------------------------------------------------------------
# System tool requirements
# ------------------------------------------------------------

.PHONY: require-awk
require-awk:
	@command -v awk >/dev/null 2>&1 || \
	( echo "❌ awk not found — install via system package manager"; exit 1 )

.PHONY: require-aspell
require-aspell:
	@command -v aspell >/dev/null 2>&1 || \
	( echo "❌ aspell missing — install with: sudo apt install aspell"; exit 1 )

# ------------------------------------------------------------
# Best-effort dev tooling
# ------------------------------------------------------------

.PHONY: checkmake
checkmake:
	@mkdir -p $(TOOLS_DIR)
	@echo "⚠️  Installing checkmake (best-effort, requires modern Go)"
	@GOBIN=$(abspath $(TOOLS_DIR)) \
		go install github.com/checkmake/checkmake@latest || \
		echo "⚠️  checkmake install failed — continuing without it"

# ------------------------------------------------------------
# Linting (advisory)
# ------------------------------------------------------------

.PHONY: lint
lint:
	@if [ -x "$(CHECKMAKE)" ]; then \
		$(CHECKMAKE) Makefile || true; \
	else \
		echo "⚠️  checkmake not installed — skipping lint"; \
	fi

# ------------------------------------------------------------
# Spell checking
# ------------------------------------------------------------

.PHONY: spellcheck
spellcheck: require-aspell
	@for f in $(SPELLCHECK_FILES); do \
		aspell check "$$f"; \
	done

.PHONY: spellcheck-comments
spellcheck-comments: require-aspell
	@sed -n 's/^[[:space:]]*#//p' $(SPELLCHECK_MAKEFILES) | \
		aspell list | sort -u

# ------------------------------------------------------------
# Cleanup (local only)
# ------------------------------------------------------------

.PHONY: distclean
distclean:
	@rm -rf $(TOOLS_DIR)
