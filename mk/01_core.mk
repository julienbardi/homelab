# mk/01_core.mk
# IFC core paths
IFC_ROOT        ?= /var/lib/homelab
IFC_GC_SCRIPT   ?= $(INSTALL_PATH)/ifc-gc.sh
IFC_INSTALLER   ?= $(INSTALL_PATH)/install_url_file_if_changed.sh
IFC_STATUS_SCRIPT ?= $(INSTALL_PATH)/ifc-status.sh

.PHONY: ifc-gc
ifc-gc: install-all ensure-ifc-root
	@echo "🧹 IFC GC: cleaning $(IFC_ROOT)"
	@$(run_as_root) sh -c '"$(IFC_GC_SCRIPT)" "$(IFC_ROOT)" "$(IFC_GC_TTL)"'

# Default TTL for GC (7 days)
IFC_GC_TTL ?= 604800

.PHONY: ifc-maintenance
ifc-maintenance: install-all ensure-ifc-root ifc-gc
	@echo "🧼 IFC maintenance complete"

# IFC status tool
.PHONY: ifc-status
ifc-status: install-all ensure-ifc-root
	@echo "📊 IFC status for $(IFC_ROOT)"
	@$(run_as_root) "$(IFC_STATUS_SCRIPT)" "$(IFC_ROOT)"

# Ensure IFC_ROOT exists with correct ownership and permissions
.PHONY: ensure-ifc-root
ensure-ifc-root:
	@$(run_as_root) sh -c '\
		install -d -m 0755 -o $(ROOT_UID) -g $(ROOT_GID) "$(IFC_ROOT)"; \
		install -d -m 0755 -o $(ROOT_UID) -g $(ROOT_GID) "$(IFC_ROOT)/objects"; \
		install -d -m 0755 -o $(ROOT_UID) -g $(ROOT_GID) "$(IFC_ROOT)/refs"; \
	'
