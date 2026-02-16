from dataclasses import dataclass

PLAN_COLUMNS = [
    "node",
    "iface",
    "profile",
    "tunnel_mode",
    "lan_access",
    "egress_v4",
    "egress_v6",
    "client_addr_v4",
    "client_addr_v6",
    "client_allowed_ips_v4",
    "client_allowed_ips_v6",
    "server_allowed_ips_v4",
    "server_allowed_ips_v6",
    "dns",
]

@dataclass(frozen=True)
class PlanRow:
    node: str
    iface: str
    profile: str
    tunnel_mode: str
    lan_access: int
    egress_v4: int
    egress_v6: int
    client_addr_v4: str
    client_addr_v6: str
    client_allowed_ips_v4: str
    client_allowed_ips_v6: str
    server_allowed_ips_v4: str
    server_allowed_ips_v6: str
    dns: str
