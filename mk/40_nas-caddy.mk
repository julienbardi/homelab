# 40_nas-caddy.mk

CADDY_VERSION ?= v2.11.7
CADDY_BUILD_DIR := $(STAMP_DIR_USER)/caddy-build
CADDY_CUSTOM_BIN := $(CADDY_BUILD_DIR)/caddy
CADDY_RATE_LIMIT_MODULE := github.com/mholt/caddy-ratelimit
STAMP_CADDY_BUILD := $(call STAMP_PATH_FROM_KEY,caddy-build)

NAS_CADDY_BIN               ?= /usr/bin/caddy
NAS_CADDY_BACKUP            ?= /usr/bin/caddy.orig
NAS_STAMP_CADDY             ?= $(STAMP_DIR_ROOT)/caddy.installed

NAS_CADDYFILE               := /etc/caddy/Caddyfile
SRC_NAS_CADDYFILE           := $(REPO_ROOT)/config/caddy/Caddyfile
SRC_NAS_SERVICE             := $(REPO_ROOT)/config/caddy/caddy.service
NAS_SYSTEMD_CADDY           := /etc/systemd/system/caddy.service

.PHONY: caddy-build-local
caddy-build-local: | $(XCADDY)
	@set -euo pipefail; \
	if $(call fastpath_binary_with_stamp,$(STAMP_CADDY_BUILD),$(CADDY_CUSTOM_BIN),caddy); then \
		echo "⏩ caddy $(CADDY_VERSION) unchanged (hash+stamp OK)"; \
		exit 0; \
	fi; \
	mkdir -p "$(CADDY_BUILD_DIR)"; \
	"$(XCADDY)" build "$(CADDY_VERSION)" \
		--output "$(CADDY_CUSTOM_BIN)" \
		--with "$(CADDY_RATE_LIMIT_MODULE)"; \
	$(call write_stamp,$(STAMP_CADDY_BUILD),$(CADDY_VERSION),$(CADDY_CUSTOM_BIN))

.PHONY: caddy-build-verify
caddy-build-verify: caddy-build-local
	@"$(CADDY_CUSTOM_BIN)" version
	@"$(CADDY_CUSTOM_BIN)" list-modules | \
		grep '^http.handlers.rate_limit$$'

.PHONY: nas-caddy-dirs
nas-caddy-dirs: | $(run_as_root) $(ENSURE_DIRS)
	@rc=0; \
	$(run_as_root) $(ENSURE_DIRS) \
		/etc/caddy root root 0755 \
		/etc/ssl/caddy root caddy 0750 \
	|| rc=$$?; \
	case "$$rc" in \
	0|3) ;; \
	*) exit "$$rc" ;; \
	esac

.PHONY: deploy-nas-caddyfile
deploy-nas-caddyfile: nas-caddy-dirs | $(run_as_root) $(INSTALL_FILE_IF_CHANGED)
	@if [ "$(VERBOSE)" -ge "1" ]; then \
		echo "📋 Checking deployed Caddyfile drift..."; \
	fi; \
	changed=0; \
	rc=0; \
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) \
	"" "" "$(SRC_NAS_CADDYFILE)" \
	"" "" "$(NAS_CADDYFILE)" \
	root root 0644 || rc=$$?; \
	case "$$rc" in \
	$(INSTALL_IF_CHANGED_EXIT_UNCHANGED)) ;; \
	$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
	*) exit "$$rc" ;; \
	esac; \
	\
	if [ "$$changed" -eq 1 ]; then \
		echo "🔍 Validating Caddyfile"; \
		$(run_as_root) "$(NAS_CADDY_BIN)" validate --config "$(NAS_CADDYFILE)"; \
		\
		if $(run_as_root) systemctl is-active --quiet caddy; then \
			if ! $(run_as_root) "$(NAS_CADDY_BIN)" reload --config "$(NAS_CADDYFILE)"; then \
				echo "⚠️ Reload failed. Restarting service..."; \
				$(run_as_root) systemctl restart caddy; \
			else \
				echo "✅ Reloaded Caddy successfully"; \
			fi; \
		else \
			echo "ℹ️ Caddy not running; skipping reload"; \
		fi; \
	fi

.PHONY: nas-caddy
nas-caddy: \
	gitcheck \
	nas-assert-caddy-ports-free \
	acme-issue \
	deploy-caddy \
	nas-caddy-dirs \
	deploy-nas-caddyfile \
	| $(run_as_root) \
	  $(INSTALL_FILE_IF_CHANGED) \
	  $(ENSURE_DIRS)
	@set -euo pipefail; \
	echo "🔐 Ensuring Caddy system users/groups"; \
	$(run_as_root) bash -c 'set -euo pipefail; \
	if ! getent group caddy >/dev/null 2>&1; then \
		groupadd --system caddy; \
	fi; \
	if ! getent passwd caddy >/dev/null 2>&1; then \
		useradd --system --gid caddy --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy; \
	fi; \
	'; \
	\
	echo "📋⬇️ Installing SSL Certificates"; \
	$(call install_file,$(ACME_LINEAGE_ECC)/fullchain.cer,/etc/ssl/caddy/bardi.ch.cer,root,caddy,0640); \
	$(call install_file,$(ACME_LINEAGE_ECC)/bardi.ch.key,/etc/ssl/caddy/bardi.ch.key,root,caddy,0640); \
	\
	CHANGED=0; \
	SERVICE_CHANGED=0; \
	IFC_STATUS=0; \
	\
	if [ -f "$(NAS_CADDY_BIN)" ]; then \
		cp_rc=0; \
		$(run_as_root) cmp -s "$(CADDY_CUSTOM_BIN)" "$(NAS_CADDY_BIN)" || cp_rc=1; \
		if [ "$$cp_rc" -eq 1 ]; then \
			echo "💾 Backing up existing Caddy binary"; \
			$(run_as_root) cp -f "$(NAS_CADDY_BIN)" "$(NAS_CADDY_BACKUP)"; \
			$(run_as_root) chmod 0755 "$(NAS_CADDY_BACKUP)"; \
		fi; \
	fi; \
	\
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) \
	"" "" "$(CADDY_CUSTOM_BIN)" \
	"" "" "$(NAS_CADDY_BIN)" \
	root root 0755 \
	|| IFC_STATUS=$$?; \
	\
	if [ $$IFC_STATUS -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		CHANGED=1; \
	elif [ $$IFC_STATUS -ne $(INSTALL_IF_CHANGED_EXIT_UNCHANGED) ]; then \
		exit $$IFC_STATUS; \
	fi; \
	\
	echo "📋⬇️ Installing Caddy systemd service"; \
	IFC_STATUS=0; \
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) \
	"" "" "$(SRC_NAS_SERVICE)" \
	"" "" "$(NAS_SYSTEMD_CADDY)" \
	root root 0644 \
	|| IFC_STATUS=$$?; \
	\
	if [ $$IFC_STATUS -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		CHANGED=1; \
		SERVICE_CHANGED=1; \
	elif [ $$IFC_STATUS -ne $(INSTALL_IF_CHANGED_EXIT_UNCHANGED) ]; then \
		exit $$IFC_STATUS; \
	fi; \
	\
	echo "🔍 Verifying installed Caddy and applying service"; \
	\
	$(run_as_root) "$(NAS_CADDY_BIN)" version >/dev/null 2>&1 || { \
		echo "❌ Installed Caddy not executable"; \
		[ -f "$(NAS_CADDY_BACKUP)" ] && mv "$(NAS_CADDY_BACKUP)" "$(NAS_CADDY_BIN)"; \
		exit 1; \
	}; \
	\
	$(run_as_root) "$(NAS_CADDY_BIN)" list-modules | \
	grep -q "^http.handlers.rate_limit$$" || { \
		echo "❌ rate_limit plugin not found in installed binary"; \
		[ -f "$(NAS_CADDY_BACKUP)" ] && mv "$(NAS_CADDY_BACKUP)" "$(NAS_CADDY_BIN)"; \
		exit 1; \
	}; \
	\
	VERSION=$$($(run_as_root) "$(NAS_CADDY_BIN)" version); \
	echo "✅ Caddy verified with rate_limit plugin: $$VERSION"; \
	tmp_stamp="$$(mktemp)"; \
	printf "version=%s\n" "$$VERSION" > "$$tmp_stamp"; \
	$(call install_file,$$tmp_stamp,$(NAS_STAMP_CADDY),$(ROOT_UID),$(ROOT_GID),0644); \
	rm -f "$$tmp_stamp"; \
	\
	if [ "$$SERVICE_CHANGED" -eq 1 ]; then \
		echo "🔄 Reloading systemd units"; \
		$(run_as_root) systemctl daemon-reload; \
		$(run_as_root) systemctl enable caddy >/dev/null 2>&1 || true; \
	fi; \
	\
	if [ "$$CHANGED" -eq 1 ]; then \
		echo "🔄 Restarting Caddy"; \
		$(run_as_root) systemctl restart caddy; \
		echo "✅ Restarted successfully"; \
	else \
		echo "⏩ Caddy already converged"; \
	fi

.PHONY: nas-caddy-validate nas-caddy-fmt
nas-caddy-validate:
	@if ! sudo [ -f /etc/ssl/caddy/bardi.ch.cer ]; then \
	  echo "⚠️ Certs missing (/etc/ssl/caddy/bardi.ch.cer); skipping full validation"; \
	  echo "➡️ Run 'make deploy-caddy' or 'make nas-caddy' once to install certs."; \
	  exit 0; \
	fi
	@echo "🔍 Validating Caddyfile"
	@sudo "$(NAS_CADDY_BIN)" validate --config "$(SRC_NAS_CADDYFILE)"

nas-caddy-fmt:
	@echo " Formatting Caddyfile"
	@sudo "$(NAS_CADDY_BIN)" fmt --overwrite "$(SRC_NAS_CADDYFILE)"

.PHONY: free-web-ports
free-web-ports:
	@echo "🛑 Stopping and removing conflicting netbird-traefik proxy..."
	@container_id=$$(docker ps -q --filter "name=netbird-traefik" 2>/dev/null || true); \
	if [ -n "$$container_id" ]; then \
		docker stop $$container_id; \
		docker rm $$container_id; \
		echo "🟢 Conflicting proxy container removed successfully."; \
	else \
		echo "ℹ️ No netbird-traefik container found running."; \
	fi

.PHONY: nas-assert-caddy-ports-free
nas-assert-caddy-ports-free:
	@conflict=$$($(run_as_root) ss -H -tlnp '( sport = :80 or sport = :443 )' | grep -v caddy || true); \
	if [ -n "$$conflict" ]; then \
		echo "❌ ERROR: Port 80 or 443 is already in use:"; \
		echo "$$conflict"; \
		echo ""; \
		echo "➡️ To automatically free ports 80/443 by stopping the conflicting container, run:"; \
		echo "   make free-web-ports nas-caddy"; \
		echo ""; \
		exit 1; \
	fi