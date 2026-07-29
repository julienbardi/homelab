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

PREREQS_PACKAGES := \
	apt-cacher-ng \
	aspell \
	aspell-en \
	ndppd \
	wireguard-tools \
	unzip \
	qrencode \
	ldnsutils \
	coreutils util-linux

PREREQS_SOURCES := \
	mk/00_prereqs.mk \
	mk/20_deps.mk \
	mk/71_dns-warm.mk \
	mk/00_prereqs-rust.mk

# Full prereqs execution (mutators + verifiers + apt + scripts)
prereqs-run: $(PREREQS_SOURCES) | $(STAMP_DIR_ROOT)
	@echo "🔍 Running prereqs checks (DNS, Tailscale, docs, warm, system)"

	# --- Network deps ---
	@$(call ensure_host_default_route)
	@$(call ensure_bootstrap_dns)
	@$(call prereqs_tailscale_repo_verify)
	@$(call prereqs_dns_warm)

	# --- System deps ---
	@$(call prereqs_helper_scripts)
	@$(call install_ssh_config)
	@$(call rust_system)

	# --- Verify-only ---
	@$(call prereqs_dns_warm_verify)
	@$(call prereqs_docs_verify)
	@$(call prereqs_public_dns_verify)

	# --- Apt prerequisites ---
	@echo "📦 Ensuring installation of prerequisite tools"
	@$(call apt_install_group,$(PREREQS_PACKAGES))

	@sh -c 'for bin in curl jq git iperf3 qrencode funzip; do \
		command -v "$$bin" >/dev/null || { echo "❌ $$bin missing"; exit 1; }; \
		done; echo "✅ Base prerequisites installed"'

	# nft sanity
	@sh -c 'test -x /usr/sbin/nft || { \
		echo "❌ nft binary missing at /usr/sbin/nft"; exit 1; }; \
		echo "✅ nft present"; \
	'

prereqs-ok:
	@if [ -f "$(STAMP_PREREQS_OK)" ]; then \
		echo "⏩ prereqs-ok (fast-path OK)"; \
		exit 0; \
	fi

	# run prereqs-run inline
	$(call ensure_host_default_route)
	$(call ensure_bootstrap_dns)
	$(call prereqs_tailscale_repo_verify)
	$(call prereqs_dns_warm)
	$(call prereqs_helper_scripts)
	$(call install_ssh_config)
	$(call rust_system)
	$(call prereqs_dns_warm_verify)
	$(call prereqs_docs_verify)
	$(call prereqs_public_dns_verify)
	echo "📦 Ensuring installation of prerequisite tools"
	$(call apt_install_group,$(PREREQS_PACKAGES))
	sh -c 'for bin in curl jq git iperf3 qrencode funzip; do \
		command -v "$$bin" >/dev/null || { echo "❌ $$bin missing"; exit 1; }; \
	done; echo "✅ Base prerequisites installed"'
	sh -c 'test -x /usr/sbin/nft || { \
		echo "❌ nft binary missing at /usr/sbin/nft"; exit 1; }; \
		echo "✅ nft present"; \
	'

	@echo "ok" | $(run_as_root) tee "$(STAMP_PREREQS_OK)" >/dev/null
	@echo "✅ prereqs-ok complete"

.PHONY: reset-prereqs
reset-prereqs:
	@echo "🗑️ Resetting prereqs-ok stamp: sudo rm -f $(STAMP_PREREQS_OK)"
	@$(run_as_root) rm -f "$(STAMP_PREREQS_OK)"
	@echo "✅ prereqs-ok reset"

.PHONY: all help \
		prereqs prereqs-network prereqs-network-verify \
		prereqs-docs-verify prereqs-public-dns-verify \
		prereqs-root-ssh-key prereqs-operator-ssh-key \
		install-ssh-config fix-tailscale-repo \
		prereqs-python-venv prereqs-python-venv-verify \
		prereqs-dns-health-check-verify prereqs-tailscale-repo-verify \
		prereqs-helper-scripts

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

prereqs-public-dns-verify: | ensure-host-default-route
	@$(call WITH_SECRETS, sh -c '\
		echo "🔍 Verifying public DNS CNAME for apt.bardi.ch"; \
		out=$$(dig +short @$$PUBLIC_DNS apt.bardi.ch CNAME 2>&1); \
		case "$$out" in \
			*"network unreachable"*) \
				echo "❌ Network unreachable: NAS has no default route"; \
				echo "➡️ Fix: ip route add default via $$router_addr dev eth0"; \
				exit 1;; \
			*"no servers could be reached"*) \
				echo "❌ Cannot reach DNS server $$PUBLIC_DNS"; \
				exit 1;; \
			*"connection timed out"*) \
				echo "❌ DNS query to $$PUBLIC_DNS timed out"; \
				exit 1;; \
		esac; \
		cname=$$(printf "%s" "$$out" | sed "s/\\.$$//"); \
		if [ -z "$$cname" ]; then \
			echo "❌ ERROR: No CNAME returned for apt.bardi.ch"; \
			exit 1; \
		fi; \
		if [ "$$cname" != "$$APT_CNAME_EXPECTED" ]; then \
			echo "❌ ERROR: Public DNS misconfiguration detected"; \
			echo "   Expected: $$APT_CNAME_EXPECTED"; \
			echo "   Found:    $$cname"; \
			exit 1; \
		fi; \
		echo "✅ Public DNS CNAME is correct"; \
	')

prereqs-tailscale-repo-verify: | ensure-host-default-route
	@echo "🔍 Verifying Tailscale repo hygiene"
	@if [ -f $(TAILSCALE_REPO_FILE) ]; then \
		bad=$$(grep -Rl "pkgs.tailscale.com" /etc/apt/sources.list.d \
			| xargs -r grep -L "signed-by=$(TAILSCALE_KEYRING)"); \
		if [ -n "$$bad" ]; then \
			echo "❌ Tailscale repo missing signed-by=$(TAILSCALE_KEYRING):"; \
			echo "$$bad"; \
			echo ""; \
			echo "➡️ To repair this, run:"; \
			echo "   make fix-tailscale-repo"; \
			exit 1; \
		fi; \
	fi
	@echo "✅ Tailscale repo hygiene check passed"

# ------------------------------------------------------------
# Main Prereqs Target
# ------------------------------------------------------------

# 1. Granular network-bound prerequisites
.PHONY: prereqs-network-deps
prereqs-network-deps: ensure-host-default-route ensure-bootstrap-dns prereqs-tailscale-repo-verify prereqs-dns-warm

# 2. Granular system-bound prerequisites
.PHONY: prereqs-system-deps
prereqs-system-deps: prereqs-helper-scripts install-ssh-config rust-system

# 3. Dedicated target for Tailscale key management
$(TAILSCALE_KEYRING):
	@echo "🔐 Ensuring Tailscale APT signing key"
	@$(run_as_root) sh -c ' \
		tmp=$$(mktemp -p /run homelab.ifc.tmp.XXXXXX); \
		trap "rm -f $$tmp" EXIT; \
		curl -fsSL $(TAILSCALE_KEY_URL) -o "$$tmp"; \
		$(INSTALL_FILE_IF_CHANGED) -q "" "" "$$tmp" "" "" "$(TAILSCALE_KEYRING)" root root 0644'

# ------------------------------------------------------------
# Network & Infrastructure Mutators
# ------------------------------------------------------------

prereqs-network: prereqs-network-verify prereqs-ok | ensure-host-default-route
	@echo "📦 Networking prerequisites already ensured"

fix-tailscale-repo:
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
		tmp=$$(mktemp); trap "rm -f $$tmp" EXIT; printf "%s\n" "$(TAILSCALE_REPO_LINE)" > $$tmp; \
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
	@sh -c '\
		U_NAME=$${operator_user:-$$(id -un)}; \
		G_NAME=$${operator_group:-$$(id -gn)}; \
		U_HOME=$${operator_home:-$$HOME}; \
		sudo install -d -m 700 "$$U_HOME/.ssh"; \
		sudo chown "$$U_NAME:$$G_NAME" "$$U_HOME/.ssh"; \
		tmpfile=$$(mktemp); \
		if [ "$(SSH_PLATFORM)" = "windows" ]; then \
			sed \
				-e '\''s/ControlMaster auto/ControlMaster no/'\'' \
				-e '\''s#ControlPath ~/.ssh/cm-%r@%h:%p#ControlPath none#'\'' \
				-e '\''s/ControlPersist 10m/ControlPersist no/'\'' \
				-e '\''s/StrictHostKeyChecking .*/StrictHostKeyChecking accept-new/'\'' \
				< $(REPO_ROOT)/config/ssh_config.tmpl | envsubst > $$tmpfile; \
		else \
			envsubst < $(REPO_ROOT)/config/ssh_config.tmpl > $$tmpfile; \
		fi; \
		sudo mv $$tmpfile "$$U_HOME/.ssh/config"; \
		sudo chown "$$U_NAME:$$G_NAME" "$$U_HOME/.ssh/config"; \
		sudo chmod 600 "$$U_HOME/.ssh/config"; \
	'


prereqs-python-venv-verify:
	@python3 -c 'import venv' >/dev/null 2>&1 || { \
		echo "❌ python3-venv missing. Fix with: make prereqs-python-venv"; \
		exit 1; \
	}

PYTHON_MIN ?= 3.11.2

prereqs-python-venv: | ensure-host-default-route
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then echo " Ensuring python3-venv is installed (need >= $(PYTHON_MIN))"; fi
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

prereqs-dns-health-check-verify:
	@$(run_as_root) test -x $(INSTALL_PATH)/dns-health-check.sh || { \
		echo "❌ DNS health check script drift detected. Remediate with: sudo make install-all."; \
		exit 1; \
	}

# ------------------------------------------------------------
# Helper scripts
# ------------------------------------------------------------

# ------------------------------------------------------------
# Helper scripts
# ------------------------------------------------------------

prereqs-helper-scripts:
	@$(run_as_root) sh -c '\
		VERBOSE="$(VERBOSE)"; \
		if [ -n "$$VERBOSE" ] && [ "$$VERBOSE" != "0" ]; then echo "📦 Ensuring helper scripts are installed"; fi; \
		install -d -o root -g root -m 0755 "$(INSTALL_PATH)"; \
		install -o root -g root -m 0755 "$(REPO_ROOT)/scripts/ensure_dir.sh" "$(INSTALL_PATH)/ensure_dir.sh"; \
		if [ -f "$(REPO_ROOT)/scripts/wg-readiness-probe.sh" ]; then \
			install -o root -g root -m 0755 "$(REPO_ROOT)/scripts/wg-readiness-probe.sh" "$(INSTALL_PATH)/wg-readiness-probe.sh"; \
		fi; \
	'

.PHONY: ensure-bootstrap-dns
ensure-bootstrap-dns:
	@echo "🔍 Checking bootstrap DNS..."
	@set -euo pipefail; \
	\
	# Step 1: Try router DNS directly ($(LAN_ROUTER)) with readiness wait
	ready=0; \
	for i in 1 2 3 4 5 6 7 8 9 10; do \
		if dig @$(LAN_ROUTER) "$(DOMAIN)" +short +tries=1 +time=1 >/dev/null 2>&1; then \
			ready=1; \
			break; \
		fi; \
		sleep 0.5; \
	done; \
	if [ "$$ready" -eq 1 ]; then \
		echo "✅ Bootstrap DNS reachable via router ($(LAN_ROUTER))"; \
		exit 0; \
	fi; \
	\
	echo "⚠️ Bootstrap DNS ($(LAN_ROUTER)) unreachable, checking fallback..."; \
	\
	# ------------------------------------------------------------ \
	# Step 2: If resolvectl exists ➡️ use systemd-resolved path \
	# ------------------------------------------------------------ \
	if command -v resolvectl >/dev/null 2>&1; then \
		if resolvectl query "$(DOMAIN)" >/dev/null 2>&1; then \
			echo "✅ Fallback DNS OK via systemd-resolved"; \
			exit 0; \
		else \
			echo "❌ Fallback DNS failed via systemd-resolved"; \
			exit 1; \
		fi; \
	fi; \
	\
	# ------------------------------------------------------------ \
	# Step 3: Portable fallback for UGOS / BusyBox systems \
	# ------------------------------------------------------------ \
	# Extract first nameserver \
	ns="$$(awk '/^nameserver/ {print $$2}' /etc/resolv.conf | head -n1)"; \
	\
	# If no nameserver ➡️ inject router DNS temporarily \
	if [ -z "$$ns" ]; then \
		echo "⚠️  /etc/resolv.conf has no nameserver entry — injecting router DNS"; \
		echo "nameserver $(LAN_ROUTER)" | $(run_as_root) tee /etc/resolv.conf >/dev/null; \
		ns="$(LAN_ROUTER)"; \
	fi; \
	\
	# Try resolving using the detected or injected nameserver \
	if dig @"$$ns" "$(DOMAIN)" +short +tries=1 +time=2 >/dev/null 2>&1; then \
		echo "✅ Fallback DNS OK via /etc/resolv.conf (ns=$$ns)"; \
		exit 0; \
	fi; \
	\
	# If router DNS is dead, inject Cloudflare IPv4 temporarily  \
	if [ "$$ns" = "$(LAN_ROUTER)" ]; then \
		echo "⚠️  Router DNS unreachable — injecting Cloudflare DNS"; \
		echo "nameserver $(PUBLIC_DNS)" | $(run_as_root) tee /etc/resolv.conf >/dev/null; \
		ns="$(PUBLIC_DNS)"; \
		if dig @"$$ns" "$(DOMAIN)" +short +tries=1 +time=2 >/dev/null 2>&1; then \
			echo "✅ Fallback DNS OK via Cloudflare (ns=$$ns)"; \
			exit 0; \
		fi; \
	fi; \
	\
	echo "❌ No working DNS resolver found (router + fallback failed)"; \
	exit 1


.PHONY: ensure-dnsmasq-ready
ensure-dnsmasq-ready:
	@echo "⏳ Waiting for dnsmasq to become ready..."
	@ssh $(SSH_HOST_ROUTER) '/jffs/scripts/dnsmasq-ready.sh'
