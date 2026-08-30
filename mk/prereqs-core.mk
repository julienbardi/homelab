# mk/prereqs-core.mk
# ------------------------------------------------------------
# prereqs-run, prereqs-ok, stamping, apt group install
# ------------------------------------------------------------

prereqs-run: $(PREREQS_SOURCES) ensure-state-dirs
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🔍 Running prereqs checks"; fi; \
	$(call ensure_host_default_route)
	@$(call ensure_bootstrap_dns)
	@$(call prereqs_tailscale_repo_verify)
	@$(call prereqs_dns_warm)
	@$(call prereqs_helper_scripts)
	@$(call install_ssh_config)
	@$(call rust_system)
	@$(call prereqs_tailscale_install)
	@$(call prereqs_dns_warm_verify)
	@$(call prereqs_docs_verify)
	@$(call prereqs_public_dns_verify)
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "📦 Installing prerequisite tools"; fi; \
	$(call apt_install_group,$(PREREQS_PACKAGES))
	@sh -c '\
		NFT_BIN=""; \
		for candidate in /usr/sbin/nft /sbin/nft $$(command -v nft 2>/dev/null); do \
			if [ -x "$$candidate" ]; then \
				NFT_BIN="$$candidate"; \
				break; \
			fi; \
		done; \
		if [ -n "$$NFT_BIN" ] && "$$NFT_BIN" --version >/dev/null 2>&1; then \
			if [ "$(VERBOSE)" -ge 1 ]; then echo "✅ nft present ($$("$$NFT_BIN" --version))"; fi; \
		else \
			echo "❌ nft missing or invalid version"; \
			exit 1; \
		fi \
	'

prereqs-ok:
	@if [ -f "$(STAMP_PREREQS_OK)" ]; then \
		echo "⏩ prereqs-ok fast-path"; exit 0; fi

	$(call prereqs-run)
	@echo "ok" | $(run_as_root) tee "$(STAMP_PREREQS_OK)" >/dev/null
	@echo "✅ prereqs-ok complete"

reset-prereqs:
	@$(run_as_root) rm -f "$(STAMP_PREREQS_OK)"
	@echo "🗑️ prereqs-ok reset"

prereqs-network-deps: ensure-host-default-route ensure-bootstrap-dns prereqs-tailscale-repo-verify prereqs-dns-warm
prereqs-system-deps: prereqs-helper-scripts install-ssh-config rust-system
