# ============================================================
# mk/20_gitignore.mk — gitignore invariants
# ============================================================
# CONTRACT:
# - Repository root must never be ignored
# - Editor Contract artifacts must remain tracked
# - Generated control-plane artifacts must be ignored

.PHONY: lint-gitignore

lint-gitignore:
	@echo "[lint] Checking .gitignore invariants..."

	@# Repo root must not be ignored
	@if git check-ignore . >/dev/null; then \
	    echo "[lint] ERROR: repository root is ignored"; \
	    exit 1; \
	fi

	@# Editor Contract must remain enforceable
	@if git check-ignore .vscode/settings.json >/dev/null; then \
	    echo "[lint] ERROR: .vscode/settings.json is ignored"; \
	    exit 1; \
	fi

	@# Generated control-plane artifacts must be ignored
	@for f in plan.tsv alloc.tsv keys.tsv; do \
	    if ! git check-ignore $$f >/dev/null; then \
	        echo "[lint] ERROR: $$f is not ignored"; \
	        exit 1; \
	    fi; \
	done

	@echo "[lint] .gitignore invariants OK"

