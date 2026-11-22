DOCKER_DAEMON_JSON := /etc/docker/daemon.json
DOCKER_DAEMON_STAMP := $(STAMP_DIR_ROOT)/docker-daemon.stamp

.PHONY: docker-daemon

docker-daemon: ensure-state-dirs
	@tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	printf '%s\n' \
	'{' \
	'  "data-root": "/tank/docker",' \
	'  "dns": ["$(LAN_ROUTER)"]' \
	'}' > "$$tmp"; \
	rc=0; changed=0; \
	$(call install_file,$$tmp,$(DOCKER_DAEMON_JSON),$(ROOT_UID),$(ROOT_GID),0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 Docker daemon configuration changed"; \
		$($(run_as_root)) systemctl restart docker; \
	fi; \
	tmp_stamp="$$(mktemp)"; \
	printf 'dns=%s\n' "$(LAN_ROUTER)" > "$$tmp_stamp"; \
	rc=0; \
	$(call install_file,$$tmp_stamp,$(DOCKER_DAEMON_STAMP),$(ROOT_UID),$(ROOT_GID),0644) || rc=$$?; \
	rm -f "$$tmp_stamp"; \
	case "$${rc:-0}" in \
		0|$(INSTALL_IF_CHANGED_EXIT_CHANGED)) ;; \
		*) exit "$$rc" ;; \
	esac