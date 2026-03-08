# mk/python.mk
# ------------------------------------------------------------
# Python toolchain (compiler support)
# ------------------------------------------------------------

$(PYTHON_BIN):
	$(PYTHON) -m venv $(PYTHON_VENV)
	@echo "🐍 Python venv created at $(PYTHON_VENV)"

.PHONY: python-venv
python-venv: $(PYTHON_BIN)
	@echo "🐍 Python venv ready"

.PHONY: python-deps
python-deps: python-venv
	@$(PIP_BIN) install --upgrade pip
	@$(PIP_BIN) install qrcode[pil]
	@echo "📦 Python deps installed"

.PHONY: python-run
python-run: python-deps
	$(PYTHON_BIN) main.py
	@echo "▶️  Python compiler executed"
