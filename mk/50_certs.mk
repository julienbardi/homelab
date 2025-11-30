# ============================================================
# mk/50_certs.mk — Certificate orchestration
# ============================================================
# --------------------------------------------------------------------
# CONTRACT:
# - Defines run_as_root := ./bin/run-as-root
# - All recipes must call $(run_as_root) with argv tokens.
# - Do not wrap entire command in quotes.
# - Escape operators (\>, \|, \&\&, \|\|) so they survive Make parsing.
# --------------------------------------------------------------------
SCRIPT_DIR := ${HOMELAB_DIR}/scripts
DEPLOY     := $(SCRIPT_DIR)/setup/deploy_certificates.sh

.PHONY: issue renew prepare \
	deploy-% validate-% all-% \
	setup-cert-watch-% setup-cert-watch-all \
	deploy-cert-watch-% deploy-cert-watch-all \
	bootstrap-% bootstrap-all

# Base actions
issue:
	@$(run_as_root) bash $(DEPLOY) issue || { echo "[make] ❌ issue failed"; exit 1; }

renew:
	@$(run_as_root) bash $(DEPLOY) renew FORCE=$(FORCE) || { echo "[make] ❌ renew failed"; exit 1; }

prepare: renew fix-acme-perms
	@$(run_as_root) bash $(DEPLOY) prepare || { echo "[make] ❌ prepare failed"; exit 1; }

# Deploy targets (pattern rule)
deploy-%: prepare
	@$(run_as_root) bash $(DEPLOY) deploy $* || { echo "[make] ❌ deploy-$* failed"; exit 1; }

# Validate targets (pattern rule)
validate-%:
	@$(run_as_root) bash $(DEPLOY) validate $* || { echo "[make] ❌ validate-$* failed"; exit 1; }

# All-in-one targets (pattern rule: renew + prepare + deploy + validate)
all-%: renew prepare deploy-% validate-%
	@$(run_as_root) bash $(DEPLOY) all $* || { echo "[make] ❌ all-$* failed"; exit 1; }

# Cert watch setup targets
setup-cert-watch-%:
	@$(run_as_root) install -m 0644 scripts/systemd/cert-reload@.service /etc/systemd/system/cert-reload@.service \&& \
	$(run_as_root) install -m 0644 scripts/systemd/$*-cert.path /etc/systemd/system/$*-cert.path \&& \
	$(run_as_root) systemctl daemon-reload \&& \
	$(run_as_root) systemctl enable --now $*-cert.path

setup-cert-watch-all: \
	setup-cert-watch-caddy \
	setup-cert-watch-headscale \
	setup-cert-watch-coredns \
	setup-cert-watch-diskstation \
	setup-cert-watch-qnap

# Bootstrap combos (pattern rule)
bootstrap-%: setup-cert-watch-% all-%
	@echo "[make] bootstrap-$* complete"

bootstrap-all: \
	setup-cert-watch-caddy all-caddy \
	setup-cert-watch-headscale all-headscale \
	setup-cert-watch-coredns all-coredns \
	setup-cert-watch-diskstation all-diskstation \
	setup-cert-watch-qnap all-qnap

# Cert watch deploy targets
deploy-cert-watch-%:
	@$(run_as_root) install -m 0644 scripts/systemd/cert-reload@.service /etc/systemd/system/cert-reload@.service \&& \
	$(run_as_root) install -m 0644 scripts/systemd/$*-cert.path /etc/systemd/system/$*-cert.path \&& \
	$(run_as_root) systemctl daemon-reload \&& \
	$(run_as_root) systemctl enable --now $*-cert.path

deploy-cert-watch-all:
	@$(run_as_root) install -m 0644 scripts/systemd/cert-reload@.service /etc/systemd/system/cert-reload@.service \&& \
	$(run_as_root) install -m 0644 scripts/systemd/caddy-cert.path /etc/systemd/system/caddy-cert.path \&& \
	$(run_as_root) install -m 0644 scripts/systemd/headscale-cert.path /etc/systemd/system/headscale-cert.path \&& \
	$(run_as_root) install -m 0644 scripts/systemd/coredns-cert.path /etc/systemd/system/coredns-cert.path \&& \
	$(run_as_root) install -m 0644 scripts/systemd/diskstation-cert.path /etc/systemd/system/diskstation-cert.path \&& \
	$(run_as_root) install -m 0644 scripts/systemd/qnap-cert.path /etc/systemd/system/qnap-cert.path \&& \
	$(run_as_root) systemctl daemon-reload \&& \
	$(run_as_root) systemctl enable --now caddy-cert.path headscale-cert.path coredns-cert.path diskstation-cert.path qnap-cert.path
