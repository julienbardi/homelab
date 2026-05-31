# 📁 Homelab Directory Architecture
**Authoritative separation of operator configuration vs system state**

This document defines the canonical directory layout for the homelab.
It establishes the privilege boundary between:

- **Operator‑authored, persistent, backed‑up configuration**
- **System‑generated, ephemeral, auto‑regenerated state**

This separation ensures:

- deterministic automation
- safe SSD replacement
- clean backups
- reproducible deployments
- correct privilege boundaries

---

# 🧱 1. Operator Domain — `/volume1/homelab/`
**Persistent, backed up, versioned, human‑authored.**
This is the *source of truth* for the entire homelab.

## ✔️ Characteristics
- Written by the operator
- Backed up by Kopia
- Survives SSD replacement
- Version‑controlled
- Never overwritten by automation
- Safe to edit

## ✔️ Contents

### 1.1 Root
| Path | Purpose |
|------|---------|
| `/volume1/homelab/homelab.env` | Global operator configuration (env vars) |
| `/volume1/homelab/docs/`       | Documentation, architecture, notes |
| `/volume1/homelab/security/`   | Security metadata (e.g., compromised_keys.tsv) |
| `/volume1/homelab/secrets/`    | Encrypted or WITH_SECRETS‑protected material |

### 1.2 WireGuard (authoritative control plane)
| Path | Purpose |
|------|---------|
| `/volume1/homelab/wireguard/input/`  | TSVs defining intent (clients, hosts, interfaces) |
| `/volume1/homelab/wireguard/bin/`    | Generation scripts (operator‑maintained) |
| `/volume1/homelab/wireguard/keys/`   | Long‑term private keys (must be backed up) |
| `/volume1/homelab/wireguard/output/` | Delivered artifacts (configs, QR codes, router configs) |

**Important:**
`wireguard/output/` stays here because it must survive SSD replacement and be backed up.

### 1.3 Git repository
Your entire repo lives under `/volume1/homelab/`.
This is the declarative configuration layer.

---

# 🧩 2. System Domain — `/var/lib/homelab/`
**Ephemeral, root‑owned, auto‑generated, not backed up.**
This is the *state directory* for automation.

## ✔️ Characteristics
- Written by automation
- Never edited manually
- Safe to delete
- Regenerated automatically
- Not backed up
- Root‑owned
- Lives on system SSD

## ✔️ Contents

### 2.1 WireGuard (generated state)
| Path | Purpose |
|------|---------|
| `/var/lib/homelab/wg-subnets.mk` | Generated subnets from wg-interfaces.tsv |
| `/var/lib/homelab/peer-map.tsv`  | Generated peer mapping                   |

### 2.2 Firewall
| Path | Purpose |
|------|---------|
| `/var/lib/homelab/nftables.applied.hash`   | Hash of applied ruleset    |
| `/var/lib/homelab/nftables.last-run.stamp` | Timestamp of last converge |

### 2.3 Certificates
| Path | Purpose |
|------|---------|
| `/var/lib/homelab/certs.last-renew.stamp`   | ACME renewal timestamp |
| `/var/lib/homelab/certs.last-deploy.stamp`  | Deployment timestamp   |
| `/var/lib/homelab/certs.last-prepare.stamp` | Pre-deploy timestamp   |

### 2.4 Headscale
| Path | Purpose |
|------|---------|
| `/var/lib/homelab/headscale-acl.processed.json`   | Processed ACL policy     |
| `/var/lib/homelab/headscale-acl.last-apply.stamp` | Last ACL apply timestamp |

### 2.5 Router deploy
| Path | Purpose |
|------|---------|
| `/var/lib/homelab/router.last-deploy.stamp` | Router cert deploy timestamp |
| `/var/lib/homelab/router.last-sync.stamp`   | Router helper sync timestamp |

### 2.6 General
| Path | Purpose |
|------|---------|
| `/var/lib/homelab/*.stamp` | Any converge marker        |
| `/var/lib/homelab/*.hash`  | Any applied hash           |
| `/var/lib/homelab/*.mk`    | Any generated Make include |

---

# 🔐 3. Privilege Boundary Summary

| Directory | Owner | Backed Up | Editable | Purpose |
|-----------|--------|-----------|----------|----------|
| `/volume1/homelab/` | julie:admin | **Yes** | **Yes** | Operator configuration & delivered artifacts |
| `/var/lib/homelab/` | root:root | **No** | No | Generated state & converge metadata |

This boundary is **non‑negotiable** for deterministic automation.

---

# 🚀 4. Why this architecture matters

### ✔️ SSD replacement becomes trivial
All operator data lives on `/volume1`.
All system state is regenerated.

### ✔️ Backups become clean
Kopia only captures what matters.

### ✔️ Make DAG becomes deterministic
Generated state is isolated and predictable.

### ✔️ Privilege boundaries are enforced
Operator writes config.
Automation writes state.

### ✔️ No drift
State is always regenerated from intent.

---

# 📊 5. Homelab Directory Architecture — Diagram

```
                          ┌──────────────────────────────────────────────┐
                          │            Operator Domain                   │
                          │        /volume1/homelab/ (persistent)        │
                          └──────────────────────────────────────────────┘
                                        ▲                 ▲
                                        │                 │
                                        │                 │
                          (authoritative inputs)   (delivered artifacts)
                                        │                 │
                                        │                 │
     ┌──────────────────────────────┬──────────────────────────────┬──────────────────────────────┐
     │ wireguard/input/             │ wireguard/bin/               │ wireguard/keys/              │
     │  - clients.tsv               │  - generation scripts        │  - long‑term private keys    │
     │  - hosts.tsv                 │                              │                              │
     │  - wg-interfaces.tsv         │                              │                              │
     └──────────────────────────────┴──────────────────────────────┴──────────────────────────────┘
                                        │
                                        │  (generation)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        wireguard/output/ (persistent)        │
                          │  - client configs                            │
                          │  - server configs                            │
                          │  - router configs                            │
                          │  - QR codes                                  │
                          └──────────────────────────────────────────────┘
                                        │
                                        │  (deployment)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │            System Domain                     │
                          │       /var/lib/homelab/ (ephemeral)          │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │
                                        │  (generated state)
                                        ▼
     ┌──────────────────────────────┬──────────────────────────────┬──────────────────────────────┐
     │ wg-subnets.mk                │ nftables.applied.hash        │ certs.last-renew.stamp       │
     │ peer-map.tsv                 │ nftables.last-run.stamp      │ certs.last-deploy.stamp      │
     │                              │                              │ headscale-acl.processed.json │
     │                              │                              │ router.last-deploy.stamp     │
     └──────────────────────────────┴──────────────────────────────┴──────────────────────────────┘
```

---

# 🔐 6. WireGuard Control‑Plane Architecture — Diagram

```
                          ┌──────────────────────────────────────────────┐
                          │            Operator Intent                   │
                          │     /volume1/homelab/wireguard/input/        │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (TSVs define desired state)
                                        │
     ┌──────────────────────────────┬──────────────────────────────┬──────────────────────────────┐
     │ wg-interfaces.tsv            │ clients.tsv                  │ hosts.tsv                    │
     │ - interface roles            │ - client identities          │ - host metadata              │
     │ - subnets                    │ - allowed IPs                │ - routing context            │
     └──────────────────────────────┴──────────────────────────────┴──────────────────────────────┘
                                        │
                                        │  (generation scripts)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │      NAS: WireGuard Config Generation         │
                          │   /volume1/homelab/wireguard/bin/*.sh         │
                          └──────────────────────────────────────────────┘
                                        │
                                        │  (produce authoritative configs)
                                        ▼
     ┌──────────────────────────────┬──────────────────────────────┬──────────────────────────────┐
     │ output/router/wgs1.conf      │ output/server/wg7.conf       │ output/clients/*.conf        │
     │ - router interface config    │ - NAS interface config       │ - client configs + QR codes  │
     └──────────────────────────────┴──────────────────────────────┴──────────────────────────────┘
                                        │
                                        │  (deployment)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Deployment to Runtime Nodes           │
                          └──────────────────────────────────────────────┘
                                        ▲                     ▲
                                        │                     │
                                        │                     │
                        (router deploy) │                     │ (NAS deploy)
                                        │                     │
                                        ▼                     ▼
     ┌──────────────────────────────┐          ┌──────────────────────────────────────────────┐
     │ Router (runtime-only)        │          │ NAS (authoritative + runtime)                │
     │ /jffs/etc/wireguard/wgs1.conf│          │ /etc/wireguard/wg7.conf                      │
     │ - no wg-quick                │          │ - wg-quick allowed                           │
     │ - kernel module only         │          │ - firewall-nas.sh applied                    │
     └──────────────────────────────┘          └──────────────────────────────────────────────┘
                                        │
                                        │  (bring-up sequence)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Bring-Up Pipeline               │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │
                                        │  (ordered DAG)
                                        ▼
     ┌──────────────────────────────┬──────────────────────────────┬──────────────────────────────┐
     │ wg-up-router                 │ wg-up-nas                    │ wg-up (aggregate)            │
     │ - modprobe wireguard         │ - waits for router           │ - full converge              │
     │ - create wgs1                │ - wg-quick up wg7            │ - generation + deploy + up   │
     │ - assign IPs                 │ - apply NAS firewall         │                              │
     └──────────────────────────────┴──────────────────────────────┴──────────────────────────────┘
                                        │
                                        │  (runtime state)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        System Domain: /var/lib/homelab/      │
                          │      (generated state, stamps, hashes)       │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │
                                        │  (subnets, peer maps, stamps)
                                        ▼
     ┌──────────────────────────────┬──────────────────────────────┬──────────────────────────────┐
     │ wg-subnets.mk                │ peer-map.tsv                 │ wg*.stamp / wg*.hash         │
     │ - router/NAS subnets         │ - peer relationships         │ - converge markers           │
     └──────────────────────────────┴──────────────────────────────┴──────────────────────────────┘
```

# 🧩 7. Make DAG — High‑Level Architecture Diagram

This diagram shows how the homelab’s Make targets form a **deterministic DAG**:

- Operator intent →
- Generation →
- Deployment →
- Bring‑up →
- Runtime state →
- Validation

No cycles.
No hidden state.
Everything flows from declarative inputs.

```
                          ┌──────────────────────────────────────────────┐
                          │            Operator Intent                   │
                          │     /volume1/homelab/{env,tsv,keys}          │
                          └──────────────────────────────────────────────┘
                                        │
                                        │  (inputs define desired state)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Preflight Layer                 │
                          │  - prereqs                                   │
                          │  - deps                                      │
                          │  - sysctl-preflight                          │
                          │  - net-tunnel-preflight                      │
                          └──────────────────────────────────────────────┘
                                        │
                                        │  (system readiness)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Generation Layer                │
                          │  - wg-generate                               │
                          │  - certs-ensure                              │
                          │  - dnsdist / unbound configs                 │
                          │  - headscale ACL processing                  │
                          └──────────────────────────────────────────────┘
                                        │
                                        │  (authoritative artifacts)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Deployment Layer                │
                          │  - wg-install-router                         │
                          │  - wg-install-nas                            │
                          │  - deploy-router-certs                       │
                          │  - deploy-caddy                              │
                          │  - deploy-headscale                          │
                          │  - deploy-dnsdist                            │
                          └──────────────────────────────────────────────┘
                                        │
                                        │  (push configs to runtime nodes)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Bring-Up Layer                  │
                          │  - wg-up-router                              │
                          │  - wg-up-nas                                 │
                          │  - router-caddy-restart                      │
                          │  - dns-warm-start                            │
                          └──────────────────────────────────────────────┘
                                        │
                                        │  (runtime activation)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Runtime State Layer             │
                          │   /var/lib/homelab/{*.stamp,*.hash,*.mk}     │
                          │  - wg-subnets.mk                             │
                          │  - peer-map.tsv                              │
                          │  - nftables.applied.hash                     │
                          │  - certs.last-deploy.stamp                   │
                          └──────────────────────────────────────────────┘
                                        │
                                        │  (state recorded for idempotence)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Validation Layer                │
                          │  - validate-router                           │
                          │  - router-health                             │
                          │  - dns-health                                │
                          │  - certs-status                              │
                          │  - firewall-nas                              │
                          └──────────────────────────────────────────────┘
                                        │
                                        │  (feedback loop)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Converged System                │
                          │  All components match declarative intent     │
                          └──────────────────────────────────────────────┘
```
# 🔐 8. Router Certificate Lifecycle — Diagram

This diagram shows the complete lifecycle of router certificates:

- Internal CA is authoritative
- NAS generates and signs router certs
- Router receives certs atomically
- Router apply script installs them into `/jffs/ssl` and `/tmp/etc`
- Validation ensures router TLS matches canonical store
- Runtime state is recorded in `/var/lib/homelab/`

```
                          ┌──────────────────────────────────────────────┐
                          │            Internal CA (NAS)                 │
                          │   /volume1/homelab/security + certs store    │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (CA is authoritative)
                                        │
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Certificate Generation (NAS)          │
                          │  - certs-ensure                              │
                          │  - certs-create (if needed)                  │
                          │  - certs-expiry                              │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (ECC key + CSR + signed cert)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Router Certificate Bundle             │
                          │  - router.key                                │
                          │  - router.crt                                │
                          │  - fullchain.pem                             │
                          └──────────────────────────────────────────────┘
                                        │
                                        │  (deployment via IFC v2)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Router Deployment Pipeline            │
                          │  make router-certs-deploy                    │
                          │   → router-bootstrap-primitives              │
                          │   → install-all                              │
                          │   → router-certs-prereqs-ssh                 │
                          │   → router-certs-prepare                     │
                          │   → deploy_with_status(router)               │
                          └──────────────────────────────────────────────┘
                                        │
                                        │  (atomic copy to router)
                                        ▼
     ┌──────────────────────────────┐          ┌──────────────────────────────────────────────┐
     │ Router: Persistent Store     │          │ Router: Runtime Store                        │
     │ /jffs/ssl/                   │          │ /tmp/etc/                                    │
     │  - privkey.pem               │          │  - cert.pem                                  │
     │  - fullchain.pem             │          │  - privkey.pem                               │
     │  - cert.pem                  │          │  - fullchain.pem                             │
     └──────────────────────────────┘          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (router apply script)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Router Apply Script (services-start)  │
                          │  - installs certs into runtime paths         │
                          │  - restarts httpd / GUI TLS                  │
                          │  - logs to /jffs/scripts/deploy_certificates │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (post-deploy validation)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Validation Pipeline (NAS)             │
                          │  make router-certs-validate                  │
                          │   - fetch router cert                        │
                          │   - compare SAN                              │
                          │   - compare expiry                           │
                          │   - compare fullchain hash                   │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (recorded for idempotence)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │   Runtime State: /var/lib/homelab/           │
                          │  - router.last-deploy.stamp                  │
                          │  - router.last-sync.stamp                    │
                          │  - certs.last-deploy.stamp                   │
                          │  - certs.last-prepare.stamp                  │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Converged Router TLS            │
                          │   Router TLS material matches canonical CA   │
                          │   SAN contract validated                     │
                          │   Expiry validated                           │
                          │   No drift                                   │
                          └──────────────────────────────────────────────┘
```
# 🌐 9. DNS Pipeline — Architecture Diagram

This diagram shows the complete DNS pipeline:

- dnsmasq = LAN forwarder
- Unbound = recursive resolver
- dnsdist = DoH/DoT frontend
- dns‑warm = cache pre‑heater
- Health checks ensure correctness
- Runtime state lives in `/var/lib/homelab/`

```
                          ┌──────────────────────────────────────────────┐
                          │            Operator Intent                   │
                          │     /volume1/homelab/{dns configs}           │
                          │     - unbound.conf fragments                 │
                          │     - dnsdist configs                        │
                          │     - warm domain lists                      │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (declarative DNS configuration)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Generation Layer                │
                          │  - deploy-unbound                            │
                          │  - deploy-dnsdist                            │
                          │  - dns-warm-install                          │
                          │  - dns-warm-now (domain list generation)     │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (push configs to runtime)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Deployment Layer                │
                          │  - install_file_if_changed_v2                │
                          │  - dnsdist config validation                 │
                          │  - dns-warm timer activation                 │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │
                                        │  (runtime DNS stack)
                                        ▼
     ┌──────────────────────────────┬──────────────────────────────┬──────────────────────────────┐
     │ dnsmasq (LAN forwarder)      │ Unbound (recursive resolver) │ dnsdist (DoH/DoT frontend)   │
     │ - listens on LAN             │ - DNSSEC validation          │ - TLS termination            │
     │ - forwards to Unbound        │ - root hints                 │ - load balancing             │
     │ - caches local hosts         │ - cache + prefetch           │ - upstream to Unbound        │
     └──────────────────────────────┴──────────────────────────────┴──────────────────────────────┘
                                        ▲
                                        │  (cache warm-up)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              dns‑warm subsystem              │
                          │  - periodic warm via systemd timer           │
                          │  - domain list regeneration                  │
                          │  - warm-up job writes state                  │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (state + telemetry)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Runtime State: /var/lib/homelab/      │
                          │  - dns-warm.last-run.stamp                   │
                          │  - dns-warm.state.json                       │
                          │  - dnsdist.applied.hash                      │
                          │  - unbound.last-deploy.stamp                 │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (health checks)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Validation Layer                │
                          │  - dns-health                                │
                          │  - dns-runtime-check                         │
                          │  - dnsdist-status                            │
                          │  - unbound-status                            │
                          │  - dns-warm-health                           │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Converged DNS Stack             │
                          │  - LAN → dnsmasq → Unbound → Internet        │
                          │  - DoH/DoT via dnsdist                       │
                          │  - Warm cache                                │
                          │  - DNSSEC validated                          │
                          │  - Deterministic + drift-free                │
                          └──────────────────────────────────────────────┘
```

# 🧠 10. Headscale ACL Pipeline — Architecture Diagram

This diagram shows the complete ACL lifecycle:

- Operator defines ACLs declaratively
- NAS preprocesses and validates ACLs
- Headscale ingests the processed ACL
- Nodes receive updated policy
- Runtime state is recorded in `/var/lib/homelab/`
- Validation ensures no drift

```
                          ┌──────────────────────────────────────────────┐
                          │            Operator Intent                   │
                          │   /volume1/homelab/headscale/acl/*.json      │
                          │   - acl.json (authoritative policy)          │
                          │   - groups, tags, users                      │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (declarative ACL definition)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │          ACL Preprocessing (NAS)             │
                          │  make headscale-acl-process                  │
                          │   - schema validation                        │
                          │   - group expansion                          │
                          │   - tag resolution                           │
                          │   - peer identity mapping                    │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (normalized ACL)
                                        ▼
                          ┌────────────────────────────────────────────────┐
                          │     Processed ACL (authoritative output)       │
                          │  /var/lib/homelab/headscale-acl.processed.json │
                          │   - flattened rules                            │
                          │   - resolved identities                        │
                          │   - deterministic ordering                     │
                          └────────────────────────────────────────────────┘
                                        ▲
                                        │  (deployment to Headscale)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Headscale Server Ingestion            │
                          │  make deploy-headscale                       │
                          │   - push processed ACL                       │
                          │   - reload headscale                         │
                          │   - verify ACL load success                  │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (policy distribution)
                                        ▼
     ┌──────────────────────────────┬──────────────────────────────┬──────────────────────────────┐
     │ Router (wgs1)                │ NAS (wg7)                    │ Clients (wgX)                │
     │ - receives ACL updates       │ - receives ACL updates       │ - receives ACL updates       │
     │ - peer restrictions applied  │ - peer restrictions applied  │ - allowed IPs updated        │
     │ - mesh connectivity updated  │ - mesh connectivity updated  │ - tags/groups enforced       │
     └──────────────────────────────┴──────────────────────────────┴──────────────────────────────┘
                                        ▲
                                        │  (runtime state + idempotence)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Runtime State: /var/lib/homelab/      │
                          │  - headscale-acl.last-apply.stamp            │
                          │  - headscale-acl.processed.json              │
                          │  - headscale.last-reload.stamp               │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (post-deploy validation)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Validation Layer                │
                          │  - headscale status                          │
                          │  - peer list validation                      │
                          │  - ACL hash comparison                       │
                          │  - drift detection                           │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │           Converged ACL State                │
                          │  - All nodes enforce same ACL                │
                          │  - No drift from operator intent             │
                          │  - Deterministic + reproducible              │
                          └──────────────────────────────────────────────┘
```
# 🔥 11. NAS Firewall Pipeline — Architecture Diagram

This diagram shows the complete NAS firewall lifecycle:

- Operator defines trusted subnets via WireGuard TSVs
- NAS generates firewall script (iptables + ip6tables)
- Script is deployed atomically
- NAS applies rules idempotently
- Runtime state is recorded in `/var/lib/homelab/`
- Validation ensures no drift

```
                          ┌──────────────────────────────────────────────┐
                          │            Operator Intent                   │
                          │   /volume1/homelab/wireguard/input/*.tsv     │
                          │   - wg-interfaces.tsv                        │
                          │   - hosts.tsv                                │
                          │   - clients.tsv                              │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (trusted subnets + roles)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │      Subnet + Peer Map Generation (NAS)      │
                          │  - wg-generate                               │
                          │  - wg-plan-subnets.sh                        │
                          │  - produces wg-subnets.mk                    │
                          │  - produces peer-map.tsv                     │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (authoritative subnet mapping)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │      Firewall Script Generation (NAS)        │
                          │  make firewall-nas                           │
                          │   - reads wg-subnets.mk                      │
                          │   - resolves ROUTER_WG_SUBNET                │
                          │   - emits firewall-nas.sh                    │
                          │   - idempotent iptables/ip6tables rules      │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (atomic deployment)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Deployment to NAS Runtime             │
                          │  - install_file_if_changed_v2                │
                          │  - /etc/wireguard/firewall-nas.sh            │
                          │  - root-owned, executable                    │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (execution during wg-up-nas)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Firewall Application (NAS)            │
                          │  - iptables -C / -I INPUT rules              │
                          │  - ip6tables -C / -I INPUT rules             │
                          │  - allow router-terminated WG clients        │
                          │  - allow both TCP + UDP                      │
                          │  - allow IPv4 + IPv6                         │
                          │  - idempotent: only inserts if missing       │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (state tracking)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        Runtime State: /var/lib/homelab/      │
                          │  - firewall.last-apply.stamp                 │
                          │  - nftables.applied.hash (if nftables used)  │
                          │  - wg-subnets.mk (source of truth)           │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (post-apply verification)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Validation Layer                │
                          │  - firewall-nas (re-run safely)              │
                          │  - router-health-strict                      │
                          │  - iptables/ip6tables audit                  │
                          │  - drift detection via hash/stamp            │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │           Converged NAS Firewall             │
                          │  - Trusted WG subnets allowed                │
                          │  - Default-deny preserved                    │
                          │  - IPv4 + IPv6 enforced                      │
                          │  - Idempotent + drift-free                   │
                          └──────────────────────────────────────────────┘
```
# 🏠 12. End‑to‑End Homelab Architecture — Diagram

This diagram ties everything together:

- Directory architecture
- WireGuard control plane
- Router + NAS roles
- DNS, Headscale, Firewall, Certs
- Deterministic Make DAG over all subsystems

```
                          ┌──────────────────────────────────────────────┐
                          │            Operator Domain                   │
                          │        /volume1/homelab/ (persistent)        │
                          │  - homelab.env                               │
                          │  - docs/                                     │
                          │  - security/                                 │
                          │  - secrets/                                  │
                          │  - wireguard/input/                          │
                          │  - headscale/acl/                            │
                          │  - dns configs                               │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (declarative intent)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │            Make DAG (Orchestrator)           │
                          │  - preflight                                 │
                          │  - generation                                │
                          │  - deployment                                │
                          │  - bring-up                                  │
                          │  - validation                                │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (subsystem targets)
                                        ▼
     ┌──────────────────────────────┬──────────────────────────────┬──────────────────────────────┐
     │ WireGuard Control Plane      │ Router Certificates          │ DNS Pipeline                 │
     │  - wg-generate               │  - certs-ensure              │  - deploy-unbound            │
     │  - wg-up-router              │  - router-certs-deploy       │  - deploy-dnsdist            │
     │  - wg-up-nas                 │  - router-certs-validate     │  - dns-warm                  │
     └──────────────────────────────┴──────────────────────────────┴──────────────────────────────┘
                                        ▲
                                        │
                                        ▼
     ┌──────────────────────────────┬──────────────────────────────┬──────────────────────────────┐
     │ Headscale ACL Pipeline       │ NAS Firewall Pipeline        │ Other Services               │
     │  - headscale-acl-process     │  - firewall-nas              │  - Caddy                     │
     │  - deploy-headscale          │  - nftables/iptables         │  - Monitoring                │
     │  - ACL validation            │  - firewall validation       │  - Backups (Kopia)           │
     └──────────────────────────────┴──────────────────────────────┴──────────────────────────────┘
                                        ▲
                                        │  (artifacts + configs)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │            Runtime Nodes                     │
                          └──────────────────────────────────────────────┘
                                        ▲                     ▲
                                        │                     │
                                        │                     │
                                        ▼                     ▼
     ┌──────────────────────────────┐          ┌──────────────────────────────────────────────┐
     │ Router (edge)                │          │ NAS (core)                                   │
     │  - wgs1 (WireGuard)          │          │  - wg7 (WireGuard)                           │
     │  - GUI TLS (router certs)    │          │  - Unbound + dnsdist + dnsmasq               │
     │  - Skynet / router firewall  │          │  - Headscale                                 │
     │  - DoH/DoT ingress (optional)│          │  - Caddy / services                          │
     └──────────────────────────────┘          └──────────────────────────────────────────────┘
                                        ▲                     ▲
                                        │                     │
                                        │                     │
                                        ▼                     ▼
     ┌──────────────────────────────┐          ┌──────────────────────────────────────────────┐
     │ WireGuard Clients            │          │ LAN Devices                                  │
     │  - laptops, phones           │          │  - PCs, TVs, IoT                             │
     │  - remote peers              │          │  - use router as default GW                  │
     │  - connect via router WG     │          │  - DNS via dnsmasq → Unbound                 │
     └──────────────────────────────┘          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (state + idempotence)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │        System Domain: /var/lib/homelab/      │
                          │  - wg-subnets.mk                             │
                          │  - peer-map.tsv                              │
                          │  - *.stamp / *.hash                          │
                          │  - headscale-acl.processed.json              │
                          │  - router.last-deploy.stamp                  │
                          │  - dns-warm.last-run.stamp                   │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │  (validation + health)
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │              Validation Layer                │
                          │  - router-health / router-health-strict      │
                          │  - dns-health                                │
                          │  - headscale status                          │
                          │  - firewall-nas                              │
                          │  - certs-status                              │
                          └──────────────────────────────────────────────┘
                                        ▲
                                        │
                                        ▼
                          ┌──────────────────────────────────────────────┐
                          │           Converged Homelab State            │
                          │  - All subsystems match declarative intent   │
                          │  - No drift                                  │
                          │  - Deterministic, reproducible, auditable    │
                          └──────────────────────────────────────────────┘
```
