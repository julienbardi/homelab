# Attic CAS Integration

This repository integrates Attic as a LAN‑local, content‑addressed cache
to accelerate downloads across the homelab.

The integration is intentionally split into server and client components
with different dependency models.

---

# Attic Server (atticd)

- Runs as a standalone systemd service
- Does not require Nix
- Installed and managed via Make targets
- Stores CAS data under ATTIC_ROOT
- Exposed on the LAN for trusted clients

The server is treated as regular infrastructure and is fully reproducible
without Nix.

---

# Attic Client (attic)

The Attic client is Nix‑native.

Upstream Attic links against libnix (nix-main) and cannot be built reliably
using Cargo alone on non‑Nix systems.

# Design decision

- The client is installed via Nix
- A small, root‑owned wrapper is installed at /usr/local/bin/attic
- The wrapper delegates execution to the user’s Nix profile
- The client is optional and never required for correctness

This avoids:
- vendoring Nix libraries
- copying binaries out of /nix/store
- polluting the system with Nix build dependencies

---

# Installing the client

On hosts with Nix installed:

make install-attic-client

This installs:
- the Attic client into the user’s Nix profile
- a root‑owned wrapper at /usr/local/bin/attic

On hosts without Nix:
- the client is not installed
- all downloads fall back to direct fetches
- no functionality is lost

---

# Directory Layout

# In the repository

scripts/bootstrap-attic.sh     server bootstrap
config/attic/config.toml       server configuration
config/systemd/attic.service   systemd unit
mk/20_attic.mk                 Makefile integration
bin/attic                      Nix client wrapper

# On the NAS

/volume1/homelab/attic/
├── config.toml
├── store/
├── index/
└── logs/

---

# Bootstrap

Run:

make attic

This is the recommended entry point.

The bootstrap process:
- Verifies /volume1 exists
- Creates /volume1/homelab/attic/
- Installs the Attic server binary
- Installs and enables the systemd service
- Starts the service

If /volume1 is missing, Attic is skipped cleanly.

---

# Makefile Integration

The file mk/20_attic.mk provides:
- deterministic hashing of URLs
- cache lookup
- cache pull
- cache push
- transparent fallback

Usage inside any Makefile target:

$(call attic_fetch,https://example.com/file.tar.gz,output.tar.gz)

Behavior:
- cache hit → instant pull
- cache miss → download + push
- Attic unavailable → direct download

No warnings, no errors, no breakage.

---

# Debugging

# Check service status

systemctl status attic

# View logs

tail -f /volume1/homelab/attic/logs/attic.log

# Check if an object exists

attic exists http://nas:8082 <hash>

# Pull manually

attic pull http://nas:8082 <hash> > file

---

# Notes

- Attic is a performance optimization, not a hard dependency
- All configuration is version‑controlled
- Runtime state lives only on /volume1
- The Makefile never breaks if Attic is missing
- The design is explicit, deterministic, and future‑proof
