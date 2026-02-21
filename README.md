This repository tracks operational and architectural work for the homelab
control plane running on a Ugreen DXP4800+ NAS and an ASUS RT-AX86U router.

It documents contracts, failure modes, and lifecycle decisions for networking,
routing, and service orchestration across the environment.

Issues are triaged by severity and worked one at a time.

## Governance model

This repository is governed by an explicit, contract‑driven architecture.

All architectural intent, invariants, and enforcement rules are defined in
`contracts.inc`, which is treated as documentation‑as‑law.

No implementation, automation, or review decision may override or reinterpret
the contracts without an explicit contract amendment.

### First steps

If you are trying to understand the current state of the system or follow
ongoing work, start with the issue tracker:

- Open issues represent active or unresolved work.
- Severity reflects operational risk, not effort.
- At most one issue is worked on at a time.

The project board reflects the authoritative execution state.

The `archive/` directory contains legacy or superseded artifacts kept for
reference only and is not part of the active control plane.

If something is unclear, unexpected, or worth investigating, open an issue to
make it explicit.
