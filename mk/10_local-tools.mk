# mk/10_local-tools.mk
# ------------------------------------------------------------
# LOCAL DEVELOPER TOOLING — DDA Logic Module
# ------------------------------------------------------------
#
# Deterministic Declarative Architecture (DDA):
#   - All policy (versions, repos, assets, checksums) is defined
#     centrally in mk/config.mk.
#   - This module contains *logic only*:
#       • bootstrapping local developer tools
#       • enforcing pinned versions
#       • verifying checksums
#       • advisory linting and spellchecking
#   - No policy, no secrets, no environment ingestion.
#
# Scope:
#   - Local workstation / NAS only
#   - MUST NOT touch router state
#   - MUST NOT mutate system-wide configuration outside the
#     declared tool installation directory
#
# Guarantees:
#   - Deterministic, idempotent tool installation
#   - Reproducible developer environment
#   - Zero drift between declared policy and installed tools
#   - Strict separation of policy (constants) and logic (this file)
#
# Tool Classes:
#   - Core tools (e.g., yq): pinned + checksum-verified
#   - System tools (awk, aspell): required but not vendored
#   - Dev tools (checkmake): best-effort, non-reproducible
# ------------------------------------------------------------

# ------------------------------------------------------------
# Local tool root
# ------------------------------------------------------------
TOOLS_DIR := $(HOME)/.local/tools

# Local tools use STAMP_DIR_USER (user-level stamps)

SPELLCHECK_FILES := *.md
SPELLCHECK_MAKEFILES := Makefile mk/*.mk

# ------------------------------------------------------------
# Deterministic local tools
# ------------------------------------------------------------

YQ := /usr/local/bin/yq
YQ_DIR := $(dir $(YQ))

ifeq ($(wildcard $(YQ)),)
$(error "❌ yq missing — run make install-yq to install pinned system-wide version")
endif

.PHONY: install-yq
install-yq: | $(INSTALL_PATH)/install_github_asset.sh
	@echo "🔧 Installing system-wide yq $(YQ_VERSION) into /usr/local/bin"
	@sudo $(INSTALL_PATH)/install_github_asset.sh \
		"$(YQ_URL)" \
		"$(YQ)" \
		"$(YQ_SHA256)" \
		"/usr/local/bin/yq.installed" \
		"yq $(YQ_VERSION)"

# ------------------------------------------------------------
# Optional dev tool (best-effort)
# ------------------------------------------------------------

CHECKMAKE := $(TOOLS_DIR)/checkmake

# ------------------------------------------------------------
# Tool bootstrap
# ------------------------------------------------------------

.PHONY: tools
tools: require-awk

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
	@mkdir -p "$(TOOLS_DIR)"
	@echo "⚠️ Installing checkmake (best-effort, requires modern Go)"
	@GOBIN=$(abspath $(TOOLS_DIR)) \
		go install github.com/checkmake/checkmake/cmd/checkmake@latest || \
		echo "⚠️ checkmake install failed — continuing without it"

# ------------------------------------------------------------
# Linting (advisory)
# ------------------------------------------------------------

.PHONY: lint
lint:
	@if [ -x "$(CHECKMAKE)" ]; then \
		"$(CHECKMAKE)" Makefile || true; \
	else \
		echo "⚠️ checkmake not installed — skipping lint"; \
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
	@rm -rf "$(TOOLS_DIR)"
