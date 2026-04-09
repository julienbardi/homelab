# ============================================================
# mk/40_wireguard_py.mk — WireGuard Python compiler
#
# - Content-addressed (SHA256)
# - Local Python venv (no system pollution)
# - No deployment, no root required
# - Produces a success stamp on clean compile
# - This module does NOT manage system packages or cache system state
# ============================================================

WG_PY_DIR        := wg

STATE_DIR        := .state
HASH_DIR         := $(STATE_DIR)/hashes
STAMP_DIR        := $(STATE_DIR)/stamps

WG_PY_VENV       := $(STATE_DIR)/venv-wg
WG_PY_PYTHON     := $(WG_PY_VENV)/bin/python
WG_PY_PIP        := $(WG_PY_VENV)/bin/pip

WG_PY_INPUT_HASH := $(HASH_DIR)/wg.py.inputs.sha256
WG_PY_STAMP      := $(STAMP_DIR)/wg.py.compile.ok
WG_PY_DEPS_STAMP := $(STAMP_DIR)/wg.py.deps.ok
WG_PY_VENV_STAMP := $(STAMP_DIR)/wg.py.venv.ok

# ------------------------------------------------------------
# Content hash (attic-style identity)
# ------------------------------------------------------------
$(WG_PY_INPUT_HASH): \
	$(WG_PY_DIR)/compile.py \
	$(WG_PY_DIR)/state.py \
	$(WG_PY_DIR)/operations.py \
	$(WG_PY_DIR)/finalize.py \
	$(WG_PY_DIR)/domain.yaml \
	$(WG_PY_DIR)/domain.tsv \
	$(WG_PY_DIR)/render/client.py \
	$(WG_PY_DIR)/render/server.py \
	$(WG_PY_DIR)/render/qr.py
	@mkdir -p $(HASH_DIR)
	@sha256sum $^ > $@


# ------------------------------------------------------------
# Python toolchain (local, idempotent)
# ------------------------------------------------------------
# Python dependencies (intent):
#   - qrcode[pil]
#   - pillow (transitive)
# These are environment requirements, not content-addressed inputs.

$(WG_PY_VENV_STAMP):
	@mkdir -p $(STATE_DIR)
	@test -x $(WG_PY_PYTHON) || python3 -m venv $(WG_PY_VENV)
	@$(run_as_root) touch $@


$(WG_PY_PYTHON): $(WG_PY_VENV_STAMP)

$(WG_PY_DEPS_STAMP): $(WG_PY_PYTHON)
	@set -e; \
	mkdir -p $(STAMP_DIR); \
	$(WG_PY_PIP) install --upgrade pip; \
	$(WG_PY_PIP) install qrcode[pil]
	@$(run_as_root) touch $@

# ------------------------------------------------------------
# Compile (guarded by content hash)
# ------------------------------------------------------------
$(WG_PY_STAMP): $(WG_PY_INPUT_HASH) $(WG_PY_DEPS_STAMP)
	@mkdir -p $(STAMP_DIR)
	@$(WG_PY_PYTHON) $(WG_PY_DIR)/compile.py
	@$(run_as_root) touch $@

# ------------------------------------------------------------
# Public target
# ------------------------------------------------------------
.PHONY: wg-compile-py
wg-compile-py: prereqs-python-venv $(WG_PY_STAMP)
