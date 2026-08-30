# mk/prereqs-tailscale.mk
# ------------------------------------------------------------
# Tailscale repo hygiene, keyring, installation
# ------------------------------------------------------------

$(TAILSCALE_KEYRING):
	@echo "🔐 Ensuring Tailscale APT signing key"
	@$(run_as_root) sh -c '\
		tmp=$$(mktemp); \
		curl -fsSL $(TAILSCALE_KEY_URL) -o "$$tmp"; \
		$(INSTALL_FILE_IF_CHANGED) -q "" "" "$$tmp" "" "" "$(TAILSCALE_KEYRING)" root root 0644; \
	'

.PHONY: fix-tailscale-repo
fix-tailscale-repo:
	@sh -c '\
		if [ ! -f "$(TAILSCALE_REPO_FILE)" ]; then \
			printf "%s\n" "$(TAILSCALE_REPO_LINE)" | sudo tee "$(TAILSCALE_REPO_FILE)" >/dev/null; \
			exit 0; \
		fi; \
		if ! grep -q "signed-by=$(TAILSCALE_KEYRING)" "$(TAILSCALE_REPO_FILE)"; then \
			tmp=$$(mktemp); printf "%s\n" "$(TAILSCALE_REPO_LINE)" > $$tmp; \
			sudo mv $$tmp "$(TAILSCALE_REPO_FILE)"; \
		fi; \
		echo "✅ Tailscale repo updated"; \
	'

.PHONY: prereqs-tailscale-install
prereqs-tailscale-install: $(TAILSCALE_KEYRING)
	@echo "📦 Ensuring Tailscale installation (Proxmox-safe)"
	@if ! dpkg-query -W -f='${Status}' tailscale 2>/dev/null | grep -q "ok installed"; then \
		echo "ℹ️ Installing Tailscale via APT"; \
		$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get update -qq; \
		$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale tailscale-archive-keyring; \
	else \
		echo "✔️ Tailscale already installed"; \
	fi