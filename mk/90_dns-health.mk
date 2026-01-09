# mk/90_dns-health.mk
DNS_CHECK_SRC ?= scripts/dns-health-check.sh
DNS_CHECK_NAME ?= dns-health-check
DNS_CHECK_BIN := $(INSTALL_PATH)/$(DNS_CHECK_NAME)

.PHONY: check-dns

check-dns: $(DNS_CHECK_BIN) dns-runtime-check
	@echo "Running DNS health check (requires sudo)..."
	@$(run_as_root) $(DNS_CHECK_BIN)
