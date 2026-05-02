# mk/05_bootstrap_acme.mk
# --------------------------------------------------------------------
# IMPORTANT: ACME MUST NEVER BE UNINSTALLED
#
# ACME_HOME (/var/lib/acme) contains:
#   - The ACME account private key (account.key)
#   - The ACME registration metadata (account.conf)
#   - The server keypair used for certificate issuance
#
# These files are the identity of this machine to the ACME CA.
# Deleting them would:
#   - Destroy the ACME account identity
#   - Force creation of a new account keypair
#   - Invalidate all existing certificates
#   - Break every dependent service (dnsdist, DoH, nginx, etc.)
#
# ROTATION POLICY:
#   - The ACME account key MUST NOT be rotated automatically.
#   - Rotation is only allowed manually, in exceptional cases
#     (e.g., confirmed key compromise).
#
# HOW TO ROTATE (manual, destructive, last-resort):
#   1. Stop all services depending on certificates.
#   2. Backup /var/lib/acme (for forensic purposes only).
#   3. Delete ONLY the ACME account identity:
#        rm -f /var/lib/acme/account.key /var/lib/acme/account.conf
#   4. Re-run `make acme-bootstrap` to create a new ACME account.
#   5. Re-issue all certificates and redeploy them.
#
# NOTE:
#   - Rotation invalidates all existing certificates.
#   - Rotation requires full redeployment of TLS material.
#   - Therefore: DO NOT ROTATE unless absolutely necessary.
#
# ACME supports bootstrap and upgrade only.
# No uninstall target must ever exist.
# --------------------------------------------------------------------

ACME_HOME    := /var/lib/acme
ACME_BIN     := $(ACME_HOME)/acme.sh
ACME_VERSION := v3.1.3

.PHONY: acme-bootstrap acme-install acme-ensure-dirs

acme-bootstrap: ensure-run-as-root acme-ensure-dirs acme-install
	@echo "✅ ACME bootstrap complete"

acme-ensure-dirs: | $(run_as_root)
	@{ \
		test -d "$(ACME_HOME)" || \
		$(run_as_root) install -d -m 0700 -o $(ROOT_UID) -g $(ROOT_GID) "$(ACME_HOME)"; \
	}

ACME_SRC := $(HOME)/src/acme.sh

acme-install: | $(run_as_root)
	@if ! command -v curl >/dev/null 2>&1; then \
		echo "❌ curl missing — required for ACME bootstrap"; \
		exit 1; \
	fi; \
	if ! command -v git >/dev/null 2>&1; then \
		echo "❌ git missing — required for ACME source sync"; \
		exit 1; \
	fi; \
	CURRENT_VER="$$( $(run_as_root) sh -c 'test -x "$(ACME_BIN)" && "$(ACME_BIN)" --version | tail -n 1 | xargs || echo none' )"; \
	if [ "$$CURRENT_VER" != "$(ACME_VERSION)" ]; then \
		echo "🔄 ACME Version mismatch (Got: $$CURRENT_VER, Target: $(ACME_VERSION)). Installing..."; \
		$(call git_clone_or_fetch,$(ACME_SRC),https://github.com/acmesh-official/acme.sh.git,master); \
		cd "$(ACME_SRC)"; \
		$(run_as_root) ./acme.sh --install --nocron --home "$(ACME_HOME)"; \
	else \
		echo "✅ acme.sh $$CURRENT_VER already installed."; \
	fi



