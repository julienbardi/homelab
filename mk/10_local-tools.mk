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
#   - Core tools (e.g., yq, checkmake): pinned + checksum-verified (via mk/20_deps.mk)
#   - System tools (awk, aspell): required but not vendored
# ------------------------------------------------------------

SPELLCHECK_FILES := *.md
SPELLCHECK_MAKEFILES := Makefile mk/*.mk

# ------------------------------------------------------------
# System-wide tool references (defined in mk/20_deps.mk)
# ------------------------------------------------------------

CHECKMAKE := $(INSTALL_PATH)/checkmake

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