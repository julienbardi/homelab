# ============================================================
# mk/20_mcp.mk
# Developer MCP tooling invariants
# ============================================================

# MCP support is a developer tooling invariant.
# Installation logic belongs in mk/10_local-tools.mk.
# This module validates that the required MCP runtime
# contract is satisfied.

.PHONY: validate-mcp-node

validate-mcp-node: install-node24
	@NODE_MAJOR="$$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"; \
	if [ "$$NODE_MAJOR" -lt 24 ]; then \
		echo "❌ MCP filesystem server requires Node.js >= 24"; \
		echo "   Installed: $$(node --version 2>/dev/null || echo missing)"; \
		exit 1; \
	fi; \
	echo "✅ Node.js $$(node --version) satisfies MCP requirements"

.PHONY: mcp-preflight

mcp-preflight: validate-mcp-node
	@echo "✅ MCP runtime prerequisites satisfied"