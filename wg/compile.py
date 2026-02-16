# =============================================================================
# WireGuard control plane — COMPILER ENTRYPOINT (DESIGN FREEZE)
#
# This file defines the authoritative control-plane compilation pipeline.
# It is documentation-as-law for how intent is resolved into realized configs.
#
# FINAL ARCHITECTURE (FROZEN):
#
#   State space:
#     - Enumerate exactly: nodes × interfaces × profiles
#     - OS (android/windows/macos) is NOT a dimension of intent
#     - OS-specific differences are handled at render time only
#
#   Profiles:
#     - Profiles are atomic, indivisible names (Model A)
#     - Each profile maps to a fixed intent vector:
#         tunnel_mode ∈ {split, full}
#         lan_access  ∈ {0,1}
#         egress_v4   ∈ {0,1}
#         egress_v6   ∈ {0,1}
#
#   Interfaces:
#     - Interfaces declare capabilities (e.g. IPv6 egress support)
#     - Interfaces declare final DNS servers (IPv4 and/or IPv6 literals)
#     - DNS selection is per-interface; profiles do not affect DNS
#
#   Compile-time rules (hard):
#     - No downgrade, no fallback: if a profile requests a capability an
#       interface does not provide, compilation MUST abort loudly.
#     - All intent is resolved at compile time; renderers MUST NOT infer policy.
#     - Server AllowedIPs are strictly the client tunnel IPs only:
#         v4: client_addr_v4/32
#         v6: client_addr_v6/128
#
#   plan.tsv (IR / debugging only):
#     - Emitted only when WG_DUMP=1
#     - Deterministic, TSV-encoded, Excel-friendly
#     - Frozen schema:
#         node, iface, profile,
#         tunnel_mode, lan_access, egress_v4, egress_v6,
#         client_addr_v4, client_addr_v6,
#         client_allowed_ips_v4, client_allowed_ips_v6,
#         server_allowed_ips_v4, server_allowed_ips_v6,
#         dns
#
#   Rendering:
#     - For each plan row (node, iface, profile), render:
#         android, windows, macos client configs
#     - OS differences are formatting/realization only
#
# CURRENT STATUS:
#   - The code below is a TEMPORARY EXPLORATION HARNESS.
#   - It mixes concerns (mutation, rendering, inspection).
#   - It MUST be refactored to match the architecture above.
#   - No new behavior may be added that contradicts this comment.
#
# Any code that violates this specification is a bug by definition.
# =============================================================================

from typing import List
from .profiles import PROFILES
from .plan import PlanRow
from .requests import PeerRequest

def compile_plan(*, interfaces, requests: List[PeerRequest]) -> List[PlanRow]:
	rows: List[PlanRow] = []

	for r in requests:
		if r.revoked:
			continue

		if r.profile not in PROFILES:
			raise ValueError(f"unknown profile: {r.profile}")

		iface = interfaces[r.iface]
		intent = PROFILES[r.profile]

		# Capability gate (example: v6 egress)
		if intent.egress_v6 and not getattr(iface, "v6_egress_capable", False):
			raise ValueError(f"profile {r.profile} requests v6 egress but iface {r.iface} is not v6-egress-capable")

		dns = ",".join(getattr(iface, "dns_servers", []))
		if not dns:
			raise ValueError(f"iface {r.iface} has no dns_servers")

		# TODO: allocate client_addr_v4/v6 and compute client_allowed_ips_* deterministically
		# For now, placeholders to keep the pipeline shape honest:
		rows.append(
			PlanRow(
				node=r.node,
				iface=r.iface,
				profile=r.profile,
				tunnel_mode=intent.tunnel_mode,
				lan_access=intent.lan_access,
				egress_v4=intent.egress_v4,
				egress_v6=intent.egress_v6,
				client_addr_v4="",
				client_addr_v6="",
				client_allowed_ips_v4="",
				client_allowed_ips_v6="",
				server_allowed_ips_v4="",
				server_allowed_ips_v6="",
				dns=dns,
			)
		)

	# Deterministic ordering
	rows.sort(key=lambda x: (x.iface, x.node, x.profile))
	return rows
