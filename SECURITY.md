# Security Policy

This repository contains automation, scripts, and configuration logic used to operate a private homelab environment.  
While the project is public, it is maintained by a single operator and is not intended for multi‑user deployments.  
Security reports are still welcome and taken seriously.

---

## Supported Versions

Only the `main` branch is maintained.  
Older commits, tags, or forks do **not** receive security updates.

| Branch / Version | Supported |
|------------------|-----------|
| `main`           | ✅ Yes    |
| anything else    | ❌ No     |

---

## Reporting a Vulnerability

If you discover a vulnerability that could:

- expose private data  
- weaken privilege boundaries  
- cause remote code execution  
- compromise WireGuard, router, or NAS automation  
- introduce unsafe defaults  
- or otherwise reduce the security of this homelab automation

please report it privately.

### How to report

Send an email to:

**25685298+julienbardi@users.noreply.github.com**

This address forwards to the maintainer without exposing a personal inbox.
Alternatively, you may open a private security advisory via  

**GitHub → Security → Advisories → Report a vulnerability**.

Include:

- a clear description of the issue  
- steps to reproduce  
- the affected file(s) or module(s)  
- any suggested fixes (optional)

### Response expectations

This project is maintained by a single operator.  
I will review reports on a best‑effort basis, but no specific response time is guaranteed.

If the issue is accepted, it will be patched on `main`.  
If the issue is declined, you will receive a brief explanation.


### Public disclosure

Please **do not** open a public GitHub issue for security‑sensitive findings.  
A coordinated disclosure timeline can be agreed upon if needed.

---

## Scope

This policy applies to:

- Makefile modules  
- router automation  
- WireGuard control plane  
- NAS scripts  
- bootstrap logic  
- configuration generators  
- firewall scripts

This policy does **not** apply to:

- upstream packages  
- vendor firmware  
- third‑party tools  
- personal infrastructure outside this repo

---

## Thank You

Responsible disclosure helps keep this homelab automation safe, reproducible, and secure.
