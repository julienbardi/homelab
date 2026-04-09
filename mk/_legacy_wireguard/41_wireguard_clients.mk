# ============================================================
# mk/41_wireguard_clients.mk — Generate clients.tsv
# ============================================================

# These variables already exist globally (from graph.mk includes)
# WG_ROOT, REPO_ROOT, run_as_root, install_file, wg-install-scripts

WG_CLIENTS_SRC := $(REPO_ROOT)/scripts/wg-generate-clients-tsv.sh
WG_CLIENTS_BIN := $(WG_ROOT)/scripts/wg-generate-clients-tsv.sh
WG_CLIENTS_TSV := $(WG_ROOT)/input/clients.tsv

# Install the generator script via IFC V2
$(WG_CLIENTS_BIN): $(WG_CLIENTS_SRC)
	$(call install_file,$(WG_CLIENTS_SRC),$(WG_CLIENTS_BIN),root,admin,0755)

# ---------------------------------------------------------------------------
# Generate TSV
# ---------------------------------------------------------------------------
.PHONY: wg-clients-generate
wg-clients-generate: wg-install-scripts $(WG_CLIENTS_BIN)
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_CLIENTS_BIN)"

# ---------------------------------------------------------------------------
# Pretty-print TSV
# ---------------------------------------------------------------------------
.PHONY: wg-clients-pretty
wg-clients-pretty: $(WG_CLIENTS_TSV)
	@column -t -s $$'\t' $(WG_CLIENTS_TSV) | less -S

# ---------------------------------------------------------------------------
# Diff (before/after generation)
# ---------------------------------------------------------------------------
.PHONY: wg-clients-generate-diff
wg-clients-generate-diff: wg-install-scripts $(WG_CLIENTS_BIN)
	@TMP=$$(mktemp); \
	cp $(WG_CLIENTS_TSV) $$TMP; \
	$(run_as_root) "$(WG_CLIENTS_BIN)"; \
	diff -u $$TMP $(WG_CLIENTS_TSV) || true; \
	rm -f $$TMP
