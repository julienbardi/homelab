# Attic CAS Integration

This repository integrates **Attic**, a content‑addressable store (CAS), to accelerate downloads across the homelab.  
Attic acts as a LAN‑local binary cache: the first machine downloads an artifact, and all others reuse it instantly.

Attic is **optional**. If it is unavailable, the Makefile transparently falls back to direct downloads.

---

## Directory Layout

### In the repo

scripts/bootstrap-attic.sh     # installs Attic on the NAS  
config/attic/config.toml       # server configuration  
systemd/attic.service          # systemd unit  
mk/20_attic.mk                 # Makefile integration  

### On the NAS

/volume1/homelab/attic/  
├── config.toml  
├── store/  
├── index/  
└── logs/  

### Binary installation

/usr/local/bin/attic-<version>  
/usr/local/bin/attic -> attic-<version>  

---

## Bootstrap

Run:

make attic

(or call `scripts/bootstrap-attic.sh` directly, but the recommended entry point is `make attic`).

The script:

- Checks if `/volume1` exists  
- Creates `/volume1/homelab/attic/`  
- Downloads the Attic binary  
- Installs the versioned binary under `/usr/local/bin`  
- Installs the systemd service  
- Starts the service  

If `/volume1` is missing, the script exits cleanly and Attic is skipped.

---

## Makefile Integration

The file `mk/20_attic.mk` provides:

- deterministic hashing of URLs  
- cache lookup  
- cache pull  
- cache push  
- transparent fallback  

Usage inside any Makefile target:

$(call attic_fetch,https://example.com/file.tar.gz,output.tar.gz)

If Attic is available:

- cache hit → instant pull  
- cache miss → download + push  

If Attic is unavailable:

- direct download  

No warnings, no errors, no breakage.

---

## Upgrading Attic

To upgrade:

1. Edit `ATTIC_VERSION` in `bootstrap-attic.sh`
2. Run:

make attic

This installs:

/usr/local/bin/attic-<newversion>  
/usr/local/bin/attic -> attic-<newversion>  

Then restart:

systemctl restart attic

Rollback is trivial:

ln -sf /usr/local/bin/attic-<oldversion> /usr/local/bin/attic  
systemctl restart attic

---

## Debugging

### Check service status

systemctl status attic

### View logs

tail -f /volume1/homelab/attic/logs/attic.log

### Check if an object exists

attic exists http://nas:8082 <hash>

### Pull manually

attic pull http://nas:8082 <hash> > file

---

## Notes

- Attic is optional; the system works without it  
- All configuration is version‑controlled  
- Runtime state lives only on `/volume1`  
- The Makefile never breaks if Attic is missing  
- The design is deterministic and future‑proof  
