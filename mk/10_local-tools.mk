# mk/10_local-tools.mk
# ------------------------------------------------------------
# LOCAL DEVELOPER TOOLING — DDA Logic Module
# ------------------------------------------------------------
#
# Deterministic Declarative Architecture (DDA):
#   - All policy (versions, repos, assets, checksums) is defined
#     centrally in mk/00_constants.mk.
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

# Local tools use user-level stamp directory
YQ_STAMP_DIR := $(STAMP_DIR_USER)
YQ_STAMP := $(YQ_STAMP_DIR)/yq.installed

SPELLCHECK_FILES := *.md
SPELLCHECK_MAKEFILES := Makefile mk/*.mk

# ------------------------------------------------------------
# Deterministic local tools
# ------------------------------------------------------------

YQ := $(TOOLS_DIR)/yq/yq
YQ_DIR := $(dir $(YQ))

# ------------------------------------------------------------
# Optional dev tool (best-effort)
# ------------------------------------------------------------

CHECKMAKE := $(TOOLS_DIR)/checkmake

# ------------------------------------------------------------
# Tool bootstrap
# ------------------------------------------------------------

.PHONY: tools
tools: STAMP_DIR := $(STAMP_DIR_USER)
tools: require-awk check-yq-latest | $(YQ_STAMP)

$(YQ_DIR):
	@mkdir -p "$@"

YQ_LATEST_CACHE := $(YQ_DIR).yq_latest_tag

.PHONY: check-yq-latest
check-yq-latest:
	@echo "🔎 checking latest yq release for $(YQ_GITHUB_REPO)"
	@$(WITH_SECRETS) \
		if [ "$${CI:-}" = "true" ]; then \
			echo "ℹ️ CI detected; skipping check-yq-latest"; \
			exit 0; \
		fi; \
		TOKEN_VAL=""; \
		[ -n "$${GITHUB_TOKEN:-}" ] && TOKEN_VAL="Authorization: token $${GITHUB_TOKEN}"; \
		if command -v jq >/dev/null 2>&1; then \
			LATEST_TAG=$$(curl -fsS -H "$$TOKEN_VAL" https://api.github.com/repos/$(YQ_GITHUB_REPO)/releases/latest | jq -r .tag_name 2>/dev/null || true); \
		else \
			LATEST_TAG=$$(curl -fsS -H "$$TOKEN_VAL" https://api.github.com/repos/$(YQ_GITHUB_REPO)/releases/latest | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null || true); \
		fi; \
		if [ -z "$$LATEST_TAG" ]; then \
			echo "⚠️ Could not determine latest yq release (GitHub API failed or rate-limited)"; \
			rm -f "$(YQ_LATEST_CACHE)"; \
		else \
			printf '%s\n' "$$LATEST_TAG" > "$(YQ_LATEST_CACHE)"; \
			echo "ℹ️ latest yq release: $$LATEST_TAG (cached at $(YQ_LATEST_CACHE))"; \
		fi

.PHONY: install-yq
# Bind STAMP_DIR locally for this target and its dependencies
install-yq: STAMP_DIR := $(STAMP_DIR_USER)
install-yq: | $(YQ_DIR) ensure-stamp-dir $(INSTALL_PATH)/install_github_asset.sh
	@$(INSTALL_PATH)/install_github_asset.sh \
		"$(YQ_URL)" \
		"$(YQ)" \
		"$(YQ_SHA256)" \
		"$(YQ_STAMP)" \
		"yq $(YQ_VERSION)"

$(YQ_STAMP): STAMP_DIR := $(STAMP_DIR_USER)
$(YQ_STAMP): install-yq
	@test -f "$@" || { echo "ERROR: expected stamp $@ missing"; exit 1; }

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
		go install github.com/checkmake/checkmake@latest || \
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
