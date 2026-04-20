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
TOOLS_DIR := $(HOME)/.local/tools

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

# yq installer (idempotent, warns on newer releases)
GITHUB_REPO := mikefarah/yq
YQ_ASSET := yq_linux_amd64

# Default: pinned version. Set to "latest" to always follow latest release.
YQ_VERSION ?= v4.53.2
# If you pin a version, optionally set the expected sha256 for verification:
YQ_SHA256 ?= d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b

YQ := $(TOOLS_DIR)/yq/yq
YQ_DIR := $(dir $(YQ))
YQ_STAMP := $(YQ_DIR).yq_installed_$(subst /,_,$(YQ_VERSION))

# tools target depends on the stamp (so changing YQ_VERSION triggers install)
.PHONY: tools
tools: require-awk check-yq-latest | $(YQ_STAMP)

# ensure yq dir exists
$(YQ_DIR):
	@mkdir -p "$@"

# cache file for latest tag
YQ_LATEST_CACHE := $(YQ_DIR).yq_latest_tag

.PHONY: check-yq-latest
check-yq-latest:
	@echo "🔎 checking latest yq release for $(GITHUB_REPO)"
	@if [ "$(CI)" = "true" ]; then \
	  echo "ℹ️  CI detected; skipping check-yq-latest"; \
	  exit 0; \
	fi; \
	# safe expansion for optional token
	if [ -n "$${GITHUB_TOKEN:-}" ]; then \
	  AUTH_HDR="-H" "Authorization: token $${GITHUB_TOKEN}"; \
	else \
	  AUTH_HDR=""; \
	fi; \
	# fetch latest tag (prefer jq)
	if command -v jq >/dev/null 2>&1; then \
	  if [ -n "$$AUTH_HDR" ]; then \
		LATEST_TAG=$$(curl -fsS $$AUTH_HDR https://api.github.com/repos/$(GITHUB_REPO)/releases/latest | jq -r .tag_name); \
	  else \
		LATEST_TAG=$$(curl -fsS https://api.github.com/repos/$(GITHUB_REPO)/releases/latest | jq -r .tag_name); \
	  fi; \
	else \
	  if [ -n "$$AUTH_HDR" ]; then \
		LATEST_TAG=$$(curl -fsS $$AUTH_HDR https://api.github.com/repos/$(GITHUB_REPO)/releases/latest | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p'); \
	  else \
		LATEST_TAG=$$(curl -fsS https://api.github.com/repos/$(GITHUB_REPO)/releases/latest | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p'); \
	  fi; \
	fi; \
	if [ -z "$$LATEST_TAG" ]; then \
	  echo "⚠️  Could not determine latest yq release (GitHub API failed or rate-limited)"; \
	  rm -f "$(YQ_LATEST_CACHE)"; \
	else \
	  echo "$$LATEST_TAG" > "$(YQ_LATEST_CACHE)"; \
	  echo "ℹ️  latest yq release: $$LATEST_TAG (cached at $(YQ_LATEST_CACHE))"; \
	fi

.PHONY: install-yq
install-yq: | $(YQ_DIR) /usr/local/bin/install_url_file_if_changed.sh
	@echo "==> install-yq: desired $(YQ_VERSION) -> $(YQ)"
	@# ensure latest-tag cache exists; if missing, fetch it inline (no recursive make)
	@if [ ! -f "$(YQ_LATEST_CACHE)" ]; then \
	  echo "ℹ️  latest tag cache missing; fetching..."; \
	  if [ -n "$${GITHUB_TOKEN:-}" ]; then AUTH_HDR="-H" "Authorization: token $${GITHUB_TOKEN}"; else AUTH_HDR=""; fi; \
	  if command -v jq >/dev/null 2>&1; then \
		if [ -n "$$AUTH_HDR" ]; then \
		  LATEST_TAG=$$(curl -fsS $$AUTH_HDR https://api.github.com/repos/$(GITHUB_REPO)/releases/latest | jq -r .tag_name 2>/dev/null || true); \
		else \
		  LATEST_TAG=$$(curl -fsS https://api.github.com/repos/$(GITHUB_REPO)/releases/latest | jq -r .tag_name 2>/dev/null || true); \
		fi; \
	  else \
		if [ -n "$$AUTH_HDR" ]; then \
		  LATEST_TAG=$$(curl -fsS $$AUTH_HDR https://api.github.com/repos/$(GITHUB_REPO)/releases/latest | sed -n 's/.*\"tag_name\":[[:space:]]*\"\([^"]*\)\".*/\1/p' 2>/dev/null || true); \
		else \
		  LATEST_TAG=$$(curl -fsS https://api.github.com/repos/$(GITHUB_REPO)/releases/latest | sed -n 's/.*\"tag_name\":[[:space:]]*\"\([^"]*\)\".*/\1/p' 2>/dev/null || true); \
		fi; \
	  fi; \
	  if [ -n "$$LATEST_TAG" ]; then printf "%s\n" "$$LATEST_TAG" > "$(YQ_LATEST_CACHE)"; echo "ℹ️  cached latest tag: $$LATEST_TAG"; else echo "⚠️  could not fetch latest tag; leaving cache missing"; fi; \
	fi; \
	\
	# read cached latest tag (may be empty)
	LATEST_TAG="$$(cat "$(YQ_LATEST_CACHE)" 2>/dev/null || true)"; \
	# determine installed version (strip leading v)
	INSTALLED="none"; \
	if [ -x "$(YQ)" ]; then INSTALLED=$$($(YQ) --version 2>/dev/null | sed -E 's/^yq version //; s/^v//'); fi; \
	INSTALLED=$$(echo $$INSTALLED | sed 's/^v//'); \
	# normalize pinned desired (strip leading v)
	PINNED=$$(echo "$(YQ_VERSION)" | sed 's/^v//'); \
	# choose desired: prefer latest tag if available, else pinned
	if [ -n "$$LATEST_TAG" ]; then DESIRED=$$(echo $$LATEST_TAG | sed 's/^v//'); else DESIRED=$$PINNED; fi; \
	echo "installed: $$INSTALLED  desired: $$DESIRED (using $$( [ -n "$$LATEST_TAG" ] && echo latest || echo pinned ))"; \
	# if installed equals desired, nothing to do
	if [ "$$INSTALLED" = "$$DESIRED" ]; then \
	  echo "✅ yq is up-to-date (version $$INSTALLED)"; \
	  exit 0; \
	fi; \
	# prepare download URL and expected checksum (only use pinned checksum when installing pinned)
	URL="https://github.com/$(GITHUB_REPO)/releases/download/v$$DESIRED/$(YQ_ASSET)"; \
	OWNER="$$(id -un)"; GROUP="$$(id -gn)"; MODE=0755; \
	if [ "$$DESIRED" = "$$PINNED" ]; then EXPECTED="$(YQ_SHA256)"; else EXPECTED=""; fi; \
	# call helper; it returns 0=no-change, 3=replaced, non-zero=error
	if /usr/local/bin/install_url_file_if_changed.sh "$$URL" "$(YQ)" "$$OWNER" "$$GROUP" "$$MODE" "$$EXPECTED"; then rc=0; else rc=$$?; fi; \
	if [ $$rc -eq 0 ] || [ $$rc -eq 3 ]; then \
	  # remove other versioned stamps to avoid accumulation
	  find "$(YQ_DIR)" -maxdepth 1 -type f -name '.yq_installed_*' -not -name '$(notdir $(YQ_STAMP))' -delete 2>/dev/null || true; \
	  # write stamp atomically
	  printf "%s\n" "$$DESIRED" > "$(YQ_STAMP).tmp" && mv "$(YQ_STAMP).tmp" "$(YQ_STAMP)"; \
	  if [ $$rc -eq 3 ]; then echo "✅ yq installed/updated to v$$DESIRED"; else echo "ℹ️  yq already up-to-date (v$$DESIRED)"; fi; \
	else \
	  echo "❌ install_url_file_if_changed.sh failed with exit $$rc"; exit $$rc; \
	fi



# stamp target depends on install-yq
$(YQ_STAMP): install-yq
	@# stamp file created by install-yq; target exists to satisfy make
	@test -f "$@" || (echo "ERROR: expected stamp $@ missing"; exit 1)


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
