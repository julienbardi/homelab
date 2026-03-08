# ------------------------------------------------------------
# LOCAL DEVELOPER TOOLING
# ------------------------------------------------------------
#
# Responsibilities:
#   - Linting and style checks
#   - Bootstrapping local tools (checkmake)
#   - Local cleanup of generated artifacts
#
# Scope:
#   - Local machine only
#   - MUST NOT touch router state
#
# Contracts:
#   - Safe to run in parallel
#   - No SSH or remote side effects
# ------------------------------------------------------------

SPELLCHECK_FILES := *.md
SPELLCHECK_MAKEFILES := Makefile mk/*.mk

AWK_BIN := $(TOOLS_DIR)/awk
AWK_URL := https://busybox.net/downloads/binaries/1.36.1-i686-uclibc/busybox
AWK_SHA256 := <PUT_THE_REAL_SHA256_HERE>

$(AWK_BIN):
	@mkdir -p $(TOOLS_DIR)
	@curl -fsSL '$(AWK_URL)' -o $@.tmp
	@echo '$(AWK_SHA256)  $@.tmp' | sha256sum -c -
	@chmod +x $@.tmp
	@mv $@.tmp $@


.PHONY: lint
lint: tools
	@$(CHECKMAKE) Makefile || true

.PHONY: tools
tools: | $(CHECKMAKE) $(TOOLS_DIR)/yq

$(CHECKMAKE):
	@mkdir -p $(TOOLS_DIR)
	@GOBIN=$(abspath $(TOOLS_DIR)) \
		go install github.com/checkmake/checkmake/cmd/checkmake@latest

YQ := $(TOOLS_DIR)/yq/yq

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
# Spell checking (local only)
# ------------------------------------------------------------

.PHONY: spellcheck
spellcheck: require-aspell
	@echo "🔤 Spellchecking files (interactive)"
	@for f in $(SPELLCHECK_FILES); do \
		echo "→ $$f"; \
		aspell check "$$f"; \
	done

.PHONY: spellcheck-comments
spellcheck-comments: require-aspell
	@echo "🔤 Spellchecking Makefile comments only"
	@sed -n 's/^[[:space:]]*#//p' $(SPELLCHECK_MAKEFILES) | \
		aspell list | sort -u

.PHONY: require-aspell
require-aspell:
	@command -v aspell >/dev/null 2>&1 || \
	( \
		echo "❌ aspell is not installed"; \
		echo "   Install it with:"; \
		echo "     sudo apt install aspell"; \
		exit 1; \
	)

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

.PHONY: distclean
distclean:
	@rm -rf $(SRC_SCRIPTS)/caddy $(TOOLS_DIR)
