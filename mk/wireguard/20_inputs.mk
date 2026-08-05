# --------------------------------------------------------------------
# mk/wireguard/20_inputs.mk — WireGuard TSV Inputs & Dynamic Lists
# --------------------------------------------------------------------

# Prevent multiple inclusion of WG DAG fragments
ifndef WG_INPUTS_INCLUDED
WG_INPUTS_INCLUDED := 1

# Serialize WG subnet generation (never parallelize)
.NOTPARALLEL: $(WG_SUBNETS_MK)

# Stamp to mark WG subnet map as up-to-date
WG_SUBNETS_STAMP := $(STAMP_DIR_ROOT)/wg-subnets.ok

# Ensure WG input directory permissions before generating any WG files
$(WG_INTERFACE_LIST_STAMP): enforce-wireguard-input
$(WG_SUBNETS_MK):
$(WG_INTERFACES_TSV): enforce-wireguard-input

# --------------------------------------------------------------------
# Generated subnet map (router + NAS WG subnets)
# --------------------------------------------------------------------
WG_SUBNETS_STAMP := $(STAMP_DIR_ROOT)/wg-subnets.ok

.PHONY: wg-subnets
wg-subnets: $(WG_ROOT)/input/wg-interfaces.tsv $(INSTALL_PATH)/wg-plan-subnets.sh ensure-stamps
	@echo "🌐 Generating WireGuard subnet map"; \
	WG_ROOT="$(WG_ROOT)" WG_SUBNETS_MK="$(WG_SUBNETS_MK)" \
		$(WG_SUDO) $(INSTALL_PATH)/wg-plan-subnets.sh
	@$(run_as_root) touch $(WG_SUBNETS_STAMP)
	@$(run_as_root) chown root:admins $(WG_SUBNETS_MK)

$(WG_SUBNETS_STAMP): wg-subnets

# Include generated WG subnet DAG fragment (only once)
-include $(WG_SUBNETS_MK)

# --------------------------------------------------------------------
# Dynamic NAS interface list
# --------------------------------------------------------------------
$(WG_INTERFACE_LIST_STAMP): \
	$(WG_ROOT)/input/wg-interfaces.tsv \
	ensure-stamps
	@echo "🔧 Generating dynamic WG interface list..."
	@awk -F'\t' '$$2=="nas" && $$1!~/^#/ {print $$1}' \
		$(WG_ROOT)/input/wg-interfaces.tsv \
		| tr '\n' ' ' \
		| sed 's/ *$$//' \
		| awk '{print "WG_INTERFACES_NAS := " $$0}' \
		> "$(WG_INTERFACE_LIST_STAMP)"

# Include NAS interface list if present
ifeq ($(wildcard $(WG_INTERFACES_MK)),)
# file missing → do nothing
else
include $(WG_INTERFACES_MK)
endif

endif
