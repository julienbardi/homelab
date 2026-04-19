ACME_HOME    := /var/lib/acme
ACME_BIN     := $(ACME_HOME)/acme.sh
ACME_VERSION := v3.1.3

.PHONY: acme-bootstrap acme-install acme-ensure-dirs

acme-bootstrap: ensure-run-as-root acme-ensure-dirs acme-install
	@echo "✅ ACME bootstrap complete"

acme-ensure-dirs:
	@if [ ! -d "$(ACME_HOME)" ]; then \
		$(run_as_root) install -d -m 0700 -o 0 -g 0 $(ACME_HOME); \
	fi

acme-install:
	@CURRENT_VER=$$($(run_as_root) sh -c 'if [ -x "$(ACME_BIN)" ]; then "$(ACME_BIN)" --version | tail -n 1 | xargs; else echo "none"; fi'); \
	if [ "$$CURRENT_VER" != "$(ACME_VERSION)" ]; then \
		echo "🔄 ACME Version mismatch (Got: $$CURRENT_VER, Target: $(ACME_VERSION)). Installing..."; \
		rm -rf /tmp/acme-src; \
		git clone --depth 1 https://github.com/acmesh-official/acme.sh.git /tmp/acme-src; \
		cd /tmp/acme-src && $(run_as_root) ./acme.sh --install --nocron --home $(ACME_HOME); \
		rm -rf /tmp/acme-src; \
	else \
		echo "✅ acme.sh $$CURRENT_VER already installed."; \
	fi