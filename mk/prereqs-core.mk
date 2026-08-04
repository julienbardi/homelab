# mk/prereqs-core.mk
# ------------------------------------------------------------
# prereqs-run, prereqs-ok, stamping, apt group install
# ------------------------------------------------------------

prereqs-run: $(PREREQS_SOURCES) ensure-stamps
	@echo "🔍 Running prereqs checks"

	@$(call ensure_host_default_route)
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

	@echo "📦 Installing prerequisite tools"
	@$(call apt_install_group,$(PREREQS_PACKAGES))

	@sh -c 'test -x /usr/sbin/nft || { echo "❌ nft missing"; exit 1; }; echo "✅ nft present"'

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
