# WireGuard Interface Contract

This document defines the **intent, invariants, and operator workflow** for the WireGuard deployment managed by this repository.
It exists to preserve correctness, prevent accidental simplification, and make future changes deliberate.

---

## 1. Interface roles

Each WireGuard interface (`wgX`) has a **fixed role** defined in `input/clients.csv` and compiled into `plan.tsv`.

Interfaces are **not interchangeable**.

### General rules

- Interface numbers are meaningful.
- Routing behavior is intentional.
- `Table = off` is used deliberately where policy routing is required.
- Interfaces may exist without active peers during compile or dry-run.

### Adding a new interface requires

- Explicit entry in `clients.csv`
- Review of routing and policy implications
- Successful `make wg-validate`
- Dry-run deploy review

No interface is ever created implicitly.

---

## 2. Invariants enforced by code

The following rules are **non-negotiable** and enforced during compile, render, and deploy.

### Configuration structure

- Server base configs **never** contain `[Peer]` sections.
- Peer stanzas are rendered separately and appended at deploy time.
- Each server config contains **exactly one** private-key placeholder.
- Placeholder replacement happens **only** during deploy.

### Deployment safety

- Deploys are atomic (`/etc/wireguard` is swapped, never edited in place).
- Failures restore the last-known-good state.
- Runtime changes occur only after a successful swap.
- Keys are never regenerated implicitly.

### Dry-run guarantees

When `WG_DRY_RUN=1` is set:

- No filesystem mutation occurs.
- No runtime WireGuard changes occur.
- No deploy lock is taken.
- Output reflects exactly what *would* change.

Dry-run must remain side-effect free.

---

## 3. Operator workflow supported paths only

These are the **only supported workflows**.

### Validate intent and render

    make wg-validate

- Compiles intent
- Renders configs
- Enforces invariants
- Performs no deployment

### Preview a deploy

    WG_DRY_RUN=1 make wg-deployed

- Builds full deploy payload
- Shows diff vs `/etc/wireguard`
- Applies nothing

### Apply a deploy

    make wg-apply

- Validates
- Deploys atomically
- Applies runtime changes
- Records deploy metadata

### Full rebuild destructive

    make wg-rebuild-all

- Invalidates all existing clients
- Regenerates keys
- Requires explicit confirmation

This is intentionally loud and slow.

---

## 4. Deploy metadata

Every successful deploy records provenance in:

    /etc/wireguard/.deploy-meta

Contents include:

- UTC timestamp
- Hostname
- Git commit hash (if available)
- Active interfaces

This file exists for **forensics and accountability**, not automation.

---

## 5. Non-goals

This system intentionally does **not** attempt to:

- Dynamically mutate peers at runtime
- Auto-heal or self-reconfigure
- Manage keys outside explicit workflows
- Hide complexity behind abstractions

Correctness and auditability are prioritized over convenience.

---

## 6. Change philosophy

If something looks “over-engineered,” it is probably protecting an invariant.

Before changing behavior:

- Identify which invariant you are relaxing
- Understand why it existed
- Update this document accordingly

If you cannot explain the change here, it should not be made.

---

This contract is part of the system.
Code changes that violate it are considered regressions.
