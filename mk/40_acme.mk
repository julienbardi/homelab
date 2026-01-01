# mk/acme.mk
# ACME certificate permission fixes

.PHONY: fix-acme-perms check-acme-perms

fix-acme-perms:
	@echo "[acme][fix] starting permission correction under ~/.acme.sh";
	@$(run_as_root) find ~/.acme.sh -type f -name "*.key" -exec chmod 600 {} \;
	@$(run_as_root) find ~/.acme.sh -type f \( -name "*.cer" -o -name "*.conf" -o -name "*.csr" -o -name "*.csr.conf" \) -exec chmod 644 {} \;
	@$(run_as_root) find ~/.acme.sh -type f -name "*.sh" -exec chmod 750 {} \;
	@$(run_as_root) find ~/.acme.sh -type d -exec chmod 750 {} \;
	@$(run_as_root) chown -R julie:admin ~/.acme.sh;
	@echo "[acme][fix] permissions corrected at $$(date '+%Y-%m-%d %H:%M:%S')"

check-acme-perms:
	@echo "[acme][check] verifying permissions under ~/.acme.sh"; \
	$(run_as_root) find ~/.acme.sh -ls | grep -E "key|cer|conf|csr|sh"
