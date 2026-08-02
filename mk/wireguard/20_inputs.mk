# --------------------------------------------------------------------
# mk/wireguard/20_inputs.mk — WireGuard TSV Inputs & Dynamic Lists
# --------------------------------------------------------------------

# Generated subnet map (router + NAS WG subnets)
$(WG_SUBNETS_MK): \
		$(WG_ROOT)/input/wg-interfaces.tsv \
		$(INSTALL_PATH)/wg-plan-subnets.sh \
		| $(STAMP_DIR_ROOT)
		@echo "🌐 Generating WireGuard subnet map"; \
		WG_ROOT="$(WG_ROOT)" WG_SUBNETS_MK="$(WG_SUBNETS_MK)" \
				$(WG_SUDO) $(INSTALL_PATH)/wg-plan-subnets.sh

-include $(WG_SUBNETS_MK)

# Dynamic NAS interface list
$(WG_INTERFACE_LIST_STAMP): $(WG_ROOT)/input/wg-interfaces.tsv | $(STAMP_DIR_ROOT)
		@echo "🔧 Generating dynamic WG interface list..."
		@awk -F'\t' '$$2=="nas" && $$1!~/^#/ {print $$1}' \
				$(WG_ROOT)/input/wg-interfaces.tsv \
				| tr '\n' ' ' \
				| sed 's/ *$$//' \
				| awk '{print "WG_INTERFACES_NAS := " $$0}' \
				> "$(WG_INTERFACE_LIST_STAMP)"

-include $(WG_INTERFACE_LIST_STAMP)
