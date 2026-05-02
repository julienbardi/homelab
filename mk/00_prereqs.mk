# mk/00_prereqs.mk
# Core tooling used across scripts
# ------------------------------------------------------------
# CONTRACT:
# - prereqs-* targets may mutate system state
# - *-verify targets never mutate state
# - installs must be idempotent
# - failures must be explicit and actionable
#
# This file must be run before any router, firewall, or WireGuard targets.
# ROLE gates prerequisites by responsibility: routers must manage NICs; services must not.
# ------------------------------------------------------------

.PHONY: all help \
		prereqs prereqs-network prereqs-network-verify \
		prereqs-docs-verify prereqs-public-dns-verify \
		prereqs-root-ssh-key prereqs-operator-ssh-key \
		install-ssh-config fix-tailscale-repo \
		prereqs-python-venv prereqs-python-venv-verify \
		prereqs-dns-health-check-verify prereqs-tailscale-repo-verify \
		prereqs-helper-scripts

PREREQ_PKGS := build-essential curl jq git nftables iptables shellcheck \
			   pup codespell aspell aspell-en ndppd knot-dnsutils \
			   unbound unbound-anchor dnsutils dnsperf iperf3 qrencode ripgrep htop \
			   libc-ares-dev apt-cacher-ng unzip git-filter-repo

# ------------------------------------------------------------
# Network & System Verification
# ------------------------------------------------------------

prereqs-network-verify:
	@command -v wg >/dev/null || { echo "❌ wireguard missing"; exit 1; }
ifeq ($(ROLE),router)
	@command -v ethtool >/dev/null || { \
		echo "❌ ethtool missing (required for ROLE=router)"; exit 1; }
	@sysctl net.ipv4.ip_forward >/dev/null 2>&1 || \
		echo "⚠️  Cannot read net.ipv4.ip_forward (sysctl unavailable?)"
else
	@command -v ethtool >/dev/null || \
		echo "ℹ️  ethtool not required for ROLE=$(ROLE)"
endif

prereqs-public-dns-verify: | ensure-default-gateway
	@$(WITH_SECRETS) \
		echo "🔍 Verifying public DNS CNAME for apt.bardi.ch"; \
		out=$$(dig +short @$$public_dns apt.bardi.ch CNAME 2>&1); \
		case "$$out" in \
			*"network unreachable"*) \
				echo "❌ Network unreachable: NAS has no default route"; \
				echo "👉 Fix: ip route add default via $$router_addr dev eth0"; \
				exit 1;; \
			*"no servers could be reached"*) \
				echo "❌ Cannot reach DNS server $$public_dns"; \
				exit 1;; \
			*"connection timed out"*) \
				echo "❌ DNS query to $$public_dns timed out"; \
				exit 1;; \
		esac; \
		cname=$$(printf "%s" "$$out" | sed 's/\.$$//'); \
		if [ -z "$$cname" ]; then \
			echo "❌ ERROR: No CNAME returned for apt.bardi.ch"; \
			exit 1; \
		fi; \
		if [ "$$cname" != "$$apt_cname_expected" ]; then \
			echo "❌ ERROR: Public DNS misconfiguration detected"; \
			echo "   Expected: $$apt_cname_expected"; \
			echo "   Found:    $$cname"; \
			exit 1; \
		fi; \
		echo "✅ Public DNS CNAME is correct"

prereqs-tailscale-repo-verify: | ensure-default-gateway
	@echo "🔍 Verifying Tailscale repo hygiene"
	@if [ -f $(TAILSCALE_REPO_FILE) ]; then \
		bad=$$(grep -Rl "pkgs.tailscale.com" /etc/apt/sources.list.d \
			| xargs -r grep -L "signed-by=$(TAILSCALE_KEYRING)"); \
		if [ -n "$$bad" ]; then \
			echo "❌ Tailscale repo missing signed-by=$(TAILSCALE_KEYRING):"; \
			echo "$$bad"; \
			echo ""; \
			echo "👉 To repair this, run:"; \
			echo "   make fix-tailscale-repo"; \
			exit 1; \
		fi; \
	fi
	@echo "✅ Tailscale repo hygiene check passed"

# ------------------------------------------------------------
# Main Prereqs Target
# ------------------------------------------------------------

prereqs: \
	ensure-run-as-root \
	ensure-default-gateway \
	prereqs-public-dns-verify \
	prereqs-tailscale-repo-verify \
	prereqs-network \
	prereqs-dns-warm-verify \
	prereqs-docs-verify \
	prereqs-helper-scripts \
	install-ssh-config \
	rust-system | ensure-default-gateway
	@echo "🔐 Ensuring Tailscale APT signing key"
	@curl -fsSL $(TAILSCALE_KEY_URL) -o /tmp/tailscale.key
	@$(call install_file,/tmp/tailscale.key,$(TAILSCALE_KEYRING),root,root,644)
	@rm -f /tmp/tailscale.key

	@echo "📦 Ensuring installation of prerequisite tools"
	@$(call apt_install_group,$(APT_CORE_PACKAGES))

	@for bin in curl jq git iperf3 qrencode funzip; do \
		command -v $$bin >/dev/null || { \
			echo "❌ $$bin missing after install"; exit 1; }; \
	done
	@test -x /usr/sbin/nft || { \
		echo "❌ nft binary missing at /usr/sbin/nft"; exit 1; }
	@echo "✅ Base prerequisites installed"

# ------------------------------------------------------------
# Network & Infrastructure Mutators
# ------------------------------------------------------------

prereqs-network: ensure-run-as-root prereqs-network-verify install-pkg-core-apt | ensure-default-gateway
	@echo "📦 Networking prerequisites already ensured"

fix-tailscale-repo: ensure-run-as-root
	@# If TAILSCALE_REPO_FILE is unset or the file is missing, print where the variable is defined
	@set -e; \
	if [ -z "$(TAILSCALE_REPO_FILE)" ] || [ ! -f "$(TAILSCALE_REPO_FILE)" ]; then \
		echo "TAILSCALE_REPO_FILE = '$(TAILSCALE_REPO_FILE)'"; \
		grep -nH -E '^[[:space:]]*TAILSCALE_REPO_FILE[[:space:]]*[:?+]?=' $(MAKEFILE_LIST) 2>/dev/null || echo "no definition found in parsed Makefiles ($(MAKEFILE_LIST))"; \
	fi
	@test -n "$(TAILSCALE_REPO_FILE)" || { echo "❌ TAILSCALE_REPO_FILE not set"; exit 1; }
	@# Ensure the repo file exists; create it if missing (idempotent)
	@sh -c '\
		if [ ! -f "$(TAILSCALE_REPO_FILE)" ]; then \
			echo "ℹ️  $(TAILSCALE_REPO_FILE) missing — creating with canonical line"; \
			printf "%s\n" "$(TAILSCALE_REPO_LINE)" | sudo tee "$(TAILSCALE_REPO_FILE)" >/dev/null; \
		fi; \
		# If already correct, do nothing and exit the same shell (prevents duplicate messages) \
		if grep -q -F "signed-by=$(TAILSCALE_KEYRING)" "$(TAILSCALE_REPO_FILE)"; then \
			echo "✅ Tailscale repo already uses signed-by=$(TAILSCALE_KEYRING)"; \
			exit 0; \
		fi; \
		# Prepare desired line and atomically update the file as root; prefer run-as-root helper, fall back to sudo \
		tmp=$$(mktemp); printf "%s\n" "$(TAILSCALE_REPO_LINE)" > $$tmp; \
		if grep -q -E "^deb .*pkgs.tailscale.com" "$(TAILSCALE_REPO_FILE)"; then \
			if [ -x /usr/local/sbin/run-as-root.sh ]; then \
				/usr/local/sbin/run-as-root.sh sh -c "sed -E '\''s|^deb .*pkgs.tailscale.com.*|$$(cat $$tmp)|'\'' '$(TAILSCALE_REPO_FILE)' > '$(TAILSCALE_REPO_FILE)'.new && mv -f '$(TAILSCALE_REPO_FILE)'.new '$(TAILSCALE_REPO_FILE)'"; \
			else \
				sudo sh -c "sed -E '\''s|^deb .*pkgs.tailscale.com.*|$$(cat $$tmp)|'\'' '$(TAILSCALE_REPO_FILE)' > '$(TAILSCALE_REPO_FILE)'.new && mv -f '$(TAILSCALE_REPO_FILE)'.new '$(TAILSCALE_REPO_FILE)'"; \
			fi; \
		else \
			if [ -x /usr/local/sbin/run-as-root.sh ]; then \
				/usr/local/sbin/run-as-root.sh sh -c "cat $$tmp >> '$(TAILSCALE_REPO_FILE)'"; \
			else \
				sudo sh -c "cat $$tmp >> '$(TAILSCALE_REPO_FILE)'"; \
			fi; \
		fi; \
		rm -f $$tmp; \
		echo "✅ Tailscale repo updated with signed-by=$(TAILSCALE_KEYRING)"; \
	'
	@# Inform about keyring if missing (non-fatal)
	@test -f "$(TAILSCALE_KEYRING)" || echo "🔐 Note: keyring $(TAILSCALE_KEYRING) not found; run 'make prereqs' to install it"

# ------------------------------------------------------------
# SSH & Identity
# ------------------------------------------------------------

prereqs-root-ssh-key:
	@key=/root/.ssh/id_ed25519; \
	if sudo test -f $$key; then \
		if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
			echo "ℹ️  Root SSH key already present"; \
		fi; \
	else \
		host=$$(hostname -s); \
		comment="$$host-root-$$(date +%F)"; \
		echo "🔐 Generating root SSH key ($$comment)"; \
		sudo mkdir -p -m 700 /root/.ssh; \
		sudo ssh-keygen -t ed25519 -f $$key -N "" -C "$$comment" </dev/null; \
		sudo chmod 600 $$key; \
		sudo chmod 644 $$key.pub; \
	fi

prereqs-operator-ssh-key:
	@key=$$HOME/.ssh/id_ed25519; \
	if [ -f $$key ]; then \
		if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
			echo "ℹ️  Operator SSH key already present"; \
		fi; \
	else \
		host=$$(hostname -s); \
		user=$$(id -un); \
		comment="$$host-operator-$$user-$$(date +%F)"; \
		echo "🔐 Generating operator SSH key ($$comment)"; \
		mkdir -p -m 700 $$HOME/.ssh; \
		ssh-keygen -t ed25519 -f $$key -N "" -C "$$comment"; \
		chmod 600 $$key; \
		chmod 644 $$key.pub; \
	fi

install-ssh-config: prereqs-operator-ssh-key
	@$(WITH_SECRETS) \
		U_NAME=$${operator_user:-$$(id -un)}; \
		G_NAME=$${operator_group:-$$(id -gn)}; \
		U_HOME=$${operator_home:-$$HOME}; \
		if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
			echo "🔧 Ensuring SSH config is up to date for $$U_NAME"; \
		fi; \
		sudo install -d -m 700 "$$U_HOME/.ssh"; \
		sudo chown "$$U_NAME:$$G_NAME" "$$U_HOME/.ssh"; \
		$(call install_file,$(REPO_ROOT)/config/ssh_config,$$U_HOME/.ssh/config,$$U_NAME,$$G_NAME,600)

prereqs-python-venv-verify:
	@python3 -c 'import venv' >/dev/null 2>&1 || { \
		echo "❌ python3-venv missing. Fix with: make prereqs-python-venv"; \
		exit 1; \
	}

PYTHON_MIN ?= 3.11.2

prereqs-python-venv: ensure-run-as-root | ensure-default-gateway
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then echo "📍 Ensuring python3-venv is installed (need >= $(PYTHON_MIN))"; fi
	@python3 -c 'import sys,importlib,pkgutil; min_ver=tuple(int(p) for p in "$(PYTHON_MIN)".split(".")); ver=tuple(sys.version_info[:len(min_ver)]); has_venv=(hasattr(importlib,"util") and importlib.util.find_spec("venv") is not None) or (pkgutil.find_loader("venv") is not None); sys.exit(0 if ver>=min_ver and has_venv else 1)' >/dev/null 2>&1 || { \
	$(call apt_update_if_needed); \
	if [ -z "$(VERBOSE)" ] || [ "$(VERBOSE)" = "0" ]; then \
		$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends python3-venv >/dev/null 2>&1; \
	else \
		$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-venv; \
	fi; \
	dpkg -s python3-venv >/dev/null 2>&1 || { echo "❌ python3-venv not installed"; exit 1; }; \
	}; \
	if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then echo "ℹ️  python3 >= $(PYTHON_MIN) and venv available: $$(python3 -V 2>&1)"; fi

prereqs-dns-health-check-verify: ensure-run-as-root
	@$(run_as_root) $(INSTALL_PATH)/dns-health-check.sh --check-only || { \
		echo "❌ DNS health check script drift detected. Remediate with: sudo make install-all."; \
		exit 1; \
	}

# ------------------------------------------------------------
# Helper scripts
# ------------------------------------------------------------

prereqs-helper-scripts: ensure-run-as-root
	@$(run_as_root) sh -c '\
		VERBOSE="$(VERBOSE)"; \
		if [ -n "$$VERBOSE" ] && [ "$$VERBOSE" != "0" ]; then echo "📦 Ensuring helper scripts are installed"; fi; \
		install -d -o root -g root -m 0755 "$(INSTALL_PATH)"; \
		install -o root -g root -m 0755 "$(REPO_ROOT)/scripts/ensure_dir.sh" "$(INSTALL_PATH)/ensure_dir.sh"; \
	'
