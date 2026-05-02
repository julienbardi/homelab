# mk/20_local-python.mk
# ------------------------------------------------------------
# Python toolchain (tooling deps, always-up-to-date)
# ------------------------------------------------------------

ifndef PYTHON_VENV
$(error PYTHON_VENV not set — local Python tooling requires an explicit venv root)
endif

ifndef PYTHON_BIN
$(error PYTHON_BIN not set — expected Python interpreter inside venv)
endif

ifndef PIP_BIN
$(error PIP_BIN not set — expected pip inside venv)
endif

PYTHON_DEPS_LOCK := $(TOOLS_DIR)/python.deps.lock
PYTHON_DEPS      := qrcode[pil]>=8.2

PYTHON_VENV_STAMP := $(PYTHON_VENV)/.venv_created
PYTHON_DEPS_STAMP := $(TOOLS_DIR)/python.deps.stamp

# ------------------------------------------------------------
# Virtualenv bootstrap (idempotent)
# ------------------------------------------------------------

$(PYTHON_VENV_STAMP):
	$(PYTHON) -m venv $(PYTHON_VENV)
	@touch "$@"
	@echo "🐍 Python venv created at $(PYTHON_VENV)"

.PHONY: python-venv
python-venv: $(PYTHON_VENV_STAMP)
	@echo "🐍 Python venv ready"

# ------------------------------------------------------------
# Toolchain policy
# ------------------------------------------------------------

.PHONY: python-pip-upgrade
python-pip-upgrade: $(PYTHON_VENV_STAMP)
	$(PIP_BIN) install --upgrade pip

# ------------------------------------------------------------
# Dependency policy (deterministic)
# ------------------------------------------------------------

$(PYTHON_DEPS_LOCK):
	@mkdir -p "$(dir $@)"
	@printf "%s\n" "$(PYTHON_DEPS)" > "$@"

$(PYTHON_DEPS_STAMP): $(PYTHON_VENV_STAMP) $(PYTHON_DEPS_LOCK)
	$(PIP_BIN) install --upgrade -r $(PYTHON_DEPS_LOCK)
	@touch "$@"
	@echo "📦 Python deps installed / updated"

.PHONY: python-deps
python-deps: $(PYTHON_DEPS_STAMP)
