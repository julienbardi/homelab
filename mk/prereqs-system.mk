# mk/prereqs-system.mk
# ------------------------------------------------------------
# SSH keys, SSH config, Python venv, Rust, helper scripts
# ------------------------------------------------------------

.PHONY: prereqs-root-ssh-key
prereqs-root-ssh-key:
	@key=/root/.ssh/id_ed25519; \
	if sudo test -f $$key; then :; else \
		host=$$(hostname -s); \
		comment="$$host-root-$$(date +%F)"; \
		echo "🔐 Generating root SSH key"; \
		sudo mkdir -p -m 700 /root/.ssh; \
		sudo ssh-keygen -t ed25519 -f $$key -N "" -C "$$comment"; \
	fi

.PHONY: prereqs-operator-ssh-key
prereqs-operator-ssh-key:
	@key=$$HOME/.ssh/id_ed25519; \
	if [ -f $$key ]; then :; else \
		host=$$(hostname -s); \
		user=$$(id -un); \
		comment="$$host-operator-$$user-$$(date +%F)"; \
		echo "🔐 Generating operator SSH key"; \
		mkdir -p -m 700 $$HOME/.ssh; \
		ssh-keygen -t ed25519 -f $$key -N "" -C "$$comment"; \
	fi
.PHONY: install-ssh-config
install-ssh-config: prereqs-operator-ssh-key
	@sh -c '\
		U_NAME=$$(id -un); \
		G_NAME=$$(id -gn); \
		U_HOME=$$HOME; \
		sudo install -d -m 700 "$$U_HOME/.ssh"; \
		tmp=$$(mktemp); \
		envsubst < $(REPO_ROOT)/config/ssh_config.tmpl > $$tmp; \
		sudo mv $$tmp "$$U_HOME/.ssh/config"; \
		sudo chmod 600 "$$U_HOME/.ssh/config"; \
	'

.PHONY: prereqs-python-venv-verify
prereqs-python-venv-verify:
	@python3 -c 'import venv' >/dev/null 2>&1 || { \
		echo "❌ python3-venv missing"; exit 1; }

.PHONY: prereqs-python-venv
prereqs-python-venv:
	@python3 -c 'import sys,importlib,pkgutil; min_ver=tuple(int(p) for p in "$(PYTHON_MIN)".split(".")); ver=tuple(sys.version_info[:len(min_ver)]); has_venv=(importlib.util.find_spec("venv") is not None); sys.exit(0 if ver>=min_ver and has_venv else 1)' >/dev/null 2>&1 || { \
	$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv; \
	}

:PHONY: prereqs-helper-scripts
prereqs-helper-scripts:
	@$(run_as_root) sh -c '\
		install -d -m 0755 "$(INSTALL_PATH)"; \
		install -m 0755 "$(REPO_ROOT)/scripts/ensure_dir.sh" "$(INSTALL_PATH)/ensure_dir.sh"; \
		if [ -f "$(REPO_ROOT)/scripts/wg-readiness-probe.sh" ]; then \
			install -m 0755 "$(REPO_ROOT)/scripts/wg-readiness-probe.sh" "$(INSTALL_PATH)/wg-readiness-probe.sh"; \
		fi; \
	'
