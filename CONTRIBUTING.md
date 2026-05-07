# Contributing

This repository contains automation and infrastructure code for a private homelab.  
While the project is public, it is maintained by a single operator and contributions are accepted only when they align with the project's architecture and standards.

## How to Contribute

### 1. Issues
Issues may be opened for:
- bugs with clear reproduction steps
- incorrect behavior in Makefile modules or scripts
- security concerns (non‑sensitive only — see SECURITY.md)
- documentation improvements

Issues will be reviewed on a best‑effort basis.

Please do **not** open issues for:
- support requests
- feature requests unrelated to the homelab architecture
- personal environment troubleshooting

### 2. Pull Requests
Pull requests are welcome if they meet all of the following:

- follow the existing style and structure  
- maintain deterministic, privilege‑correct behavior  
- do not introduce drift, dead code, or unnecessary complexity  
- include complete, literal, unshortened code (no placeholders or ellipses)  
- pass shellcheck or other linters where applicable  
- include a clear commit message describing the change

PRs that alter core architecture, privilege boundaries, or security‑sensitive logic may be declined.

### 3. Code Style

- Makefiles use **tab indentation**  
- Shell scripts must be POSIX‑compatible unless explicitly documented  
- No vendor scripts, binary blobs, or generated artifacts in version control  
- No recursive make, no quoting hell, no partial convergence  
- All paths, dependencies, and assumptions must be explicit

### 4. Security

For security‑sensitive issues, **do not** open a public issue.  
Follow the process in `SECURITY.md`.

### 5. Licensing

By submitting a contribution, you agree that your work will be licensed under the repository’s existing license.

---

Thank you for helping maintain a clean, deterministic, and secure automation environment.
