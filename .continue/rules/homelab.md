Repository Rule File
Path: .continue/rules/homelab.md

# Homelab Repository Rules

This repository is contract-governed.

## Authoritative Contracts

Authoritative contracts are defined in:

    ./contracts.md

Requirements:

- Read `./contracts.md` before reviewing, modifying, or proposing changes to any file.
- Treat `./contracts.md` as authoritative.
- Review implementation only after understanding the relevant contracts.
- If a contract and an implementation disagree, the contract wins.
- Do not reinterpret or weaken a contract without explicit instruction.

## Repository-Specific Requirements

- Prefer POSIX shell.
- Router-resident scripts must remain BusyBox compatible.
- Deployment must be atomic.
- Deployment must be idempotent.
- Privilege boundaries must be preserved.
- Single-producer authority must be preserved.
- The minimal-change principle applies.
- The Git repository is the source of truth.

## Mechanical Grounding Requirements

- Do not assume file contents.
- Do not assume repository structure.
- Do not assume dependencies exist.
- Do not assume build targets exist.
- Do not assume infrastructure exists.
- Do not claim a file is unused without evidence.
- Do not claim a target is unreachable without evidence.
- Do not claim code is dead without evidence.
- Do not claim a deployment path is unused without evidence.
- Absence of evidence is unknown, not proof.

## Evidence Requirements

Before reporting a defect:

- Identify the applicable contract.
- Identify the relevant implementation.
- Demonstrate the mismatch.
- Explain why the mismatch violates the contract.
- Provide repository evidence.
- Do not infer defects from assumptions.

Before proposing a fix:

- Prove the problem exists.
- Identify the contract being protected.
- Explain why the proposed change satisfies the contract.
- Prefer evidence over speculation.

## Review Policy

When reviewing code:

- Validate atomicity.
- Validate idempotency.
- Validate rollback safety.
- Validate portability.
- Validate privilege boundaries.
- Validate single-producer authority.
- Validate contract compliance.

For every finding:

- Cite the applicable contract.
- Cite the relevant implementation evidence.
- Explain the impact.
- Prove the problem before proposing a fix.

## Change Policy

- Prefer the smallest possible change.
- Preserve existing architecture unless explicitly instructed otherwise.
- Do not propose architectural refactors unless explicitly requested.
- Do not modify contracts unless explicitly requested.
- Do not rewrite working systems without evidence of benefit.
- If multiple solutions exist, prefer the least invasive solution that satisfies the contract.
- If uncertain, request evidence instead of guessing.

## Repository Access

Repository evidence may be obtained using the `gh` CLI.

Examples:

Search issues:

    gh issue list --repo owner/repo

View pull requests:

    gh pr list --repo owner/repo

View issue details:

    gh issue view ISSUE_NUMBER --repo owner/repo

View pull request details:

    gh pr view PR_NUMBER --repo owner/repo

Clone repository:

    gh repo clone owner/repo

## Review Output Requirements

When performing a review:

- State which contract applies.
- State which implementation was examined.
- Present evidence before conclusions.
- Distinguish facts from assumptions.
- Distinguish observations from recommendations.
- If evidence is insufficient, explicitly state that the result is unknown.
- Do not present speculation as fact.