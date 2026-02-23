# Editor Notes (Homelab)

This repository contains tab‑significant Makefiles and `.mk` includes.

## VS Code
Editor behavior is enforced via `.vscode/settings.json`:
- literal tabs
- tabSize = 4
- no auto‑indent detection
- Makefile‑safe whitespace

These settings are part of the Editor Contract and must remain committed.

## Vim / terminal editors
When editing Makefiles or `mk/*.mk` with Vim, ensure:

- `noexpandtab`
- `tabstop=4`
- `shiftwidth=4`
- `*.mk` files are treated as `filetype=make`

Example `~/.vimrc` snippet:

```vim
autocmd BufRead,BufNewFile *.mk set filetype=make
autocmd FileType make setlocal noexpandtab tabstop=4 shiftwidth=4
```

This prevents accidental space indentation in Makefile recipes.
