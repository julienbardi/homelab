# mk/15_local-python-env.mk
# ------------------------------------------------------------
# Local Python execution environment (host-only)
# ------------------------------------------------------------
#
# Scope:
#   - Local machine only
#   - Defines Python interpreter and venv layout
#   - No dependency installation here
# ------------------------------------------------------------

PYTHON      ?= python3
PYTHON_VENV ?= $(TOOLS_DIR)/venv

PYTHON_BIN  := $(PYTHON_VENV)/bin/python
PIP_BIN     := $(PYTHON_VENV)/bin/pip
