# mk/35_router-caddy-fetch.mk
# ------------------------------------------------------------
# Router Caddy binary materialization (NAS-side)
# ------------------------------------------------------------

ROUTER_CADDY_VERSION ?= 2.8.4
ROUTER_CADDY_ARCH    ?= linux_arm64
ROUTER_CADDY_URL     := https://github.com/caddyserver/caddy/releases/download/v$(ROUTER_CADDY_VERSION)/caddy_$(ROUTER_CADDY_VERSION)_$(ROUTER_CADDY_ARCH).tar.gz

$(ROUTER_CADDY_BIN): $(INSTALL_URL_FILE_IF_CHANGED)
	@echo "⬇️  Ensuring router Caddy $(ROUTER_CADDY_VERSION) ($(ROUTER_CADDY_ARCH))"
	@mkdir -p $(dir $@)
	@$(INSTALL_URL_FILE_IF_CHANGED) "$(ROUTER_CADDY_URL)" "$@" root root 0644 || [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]