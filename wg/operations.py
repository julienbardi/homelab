# operations.py

from datetime import datetime
from typing import Optional, List

from state import (
    State,
    Node,
    Peer,
    Platform,
    TunnelMode,
)

def _make_peer_id(node_id: str, iface_name: str) -> str:
    return f"{node_id}@{iface_name}"

def add_node_with_client_generated_public_key(
    *,
    state: State,
    node_id: str,
    user_id: str,
    iface_name: str,
    platform: Platform,
    tunnel_mode: TunnelMode,
    exclude_subnets: Optional[List[str]],
    public_key: str,
) -> None:
    _add_node_core(
        state=state,
        node_id=node_id,
        user_id=user_id,
        iface_name=iface_name,
        platform=platform,
        tunnel_mode=tunnel_mode,
        exclude_subnets=exclude_subnets,
        public_key=public_key,
    )

import ipaddress

def _allocate_ip_v4(state: State, iface) -> str:
    if not iface.vpn_subnet_v4:
        raise ValueError(f"Interface '{iface.iface_name}' has no IPv4 subnet")

    net = ipaddress.ip_network(iface.vpn_subnet_v4)

    # reserve network address and first host (server)
    for ip in net.hosts():
        ip_str = str(ip)
        if ip_str in state.allocations.used_ips_v4:
            continue
        state.allocations.used_ips_v4.add(ip_str)
        return ip_str

    raise RuntimeError(f"IPv4 subnet exhausted for interface '{iface.iface_name}'")

def _allocate_ip_v6(state: State, iface) -> str:
    if not iface.vpn_subnet_v6:
        raise ValueError(f"Interface '{iface.iface_name}' has no IPv6 subnet")

    net = ipaddress.ip_network(iface.vpn_subnet_v6)

    for ip in net.hosts():
        ip_str = str(ip)
        if ip_str in state.allocations.used_ips_v6:
            continue
        state.allocations.used_ips_v6.add(ip_str)
        return ip_str

    raise RuntimeError(f"IPv6 subnet exhausted for interface '{iface.iface_name}'")

# DESIGN NOTE:
# WireGuard AllowedIPs only supports positive route inclusion.
# It cannot represent "0.0.0.0/0 minus specific subnets".
# As a result, FULL tunnel exclusions (server, LAN, etc.)
# must be enforced via platform-specific routing or policy rules.
# exclude_subnets is therefore preserved in state but intentionally
# not reflected in AllowedIPs for FULL tunnel peers.

def _compute_allowed_ips(
    *,
    tunnel_mode: TunnelMode,
    iface,
    exclude_subnets: List[str],
) -> List[str]:
    if tunnel_mode == TunnelMode.FULL:
        allowed = ["0.0.0.0/0"]
        if iface.vpn_subnet_v6:
            allowed.append("::/0")
        # exclusions are handled later via platform-specific routing tricks,
        # not via WireGuard AllowedIPs (WG can't express "all except X").
        return allowed

    if tunnel_mode == TunnelMode.SPLIT:
        allowed: List[str] = []
        allowed.extend(iface.lan_subnets)
        # exclude_subnets is meaningful for split too—just subtract.
        return _subtract_subnets(allowed, exclude_subnets)

    raise ValueError(f"Unknown tunnel_mode: {tunnel_mode}")


def _subtract_subnets(allowed: List[str], exclude: List[str]) -> List[str]:
    # Minimal, explicit behavior for now: exact-string removal only.
    # (We can upgrade to CIDR containment math later, but not yet.)
    exclude_set = set(exclude or [])
    return [x for x in allowed if x not in exclude_set]


def add_node_without_any_client_generated_public_key(
    *,
    state: State,
    node_id: str,
    user_id: str,
    iface_name: str,
    platform: Platform,
    tunnel_mode: TunnelMode,
    exclude_subnets: Optional[List[str]],
) -> str:
    """
    Register a new peer with a centrally generated keypair.
    Returns the generated private key.
    """

    # placeholder key generation
    private_key = "GENERATED_PRIVATE_KEY"
    public_key = "GENERATED_PUBLIC_KEY"

    _add_node_core(
        state=state,
        node_id=node_id,
        user_id=user_id,
        iface_name=iface_name,
        platform=platform,
        tunnel_mode=tunnel_mode,
        exclude_subnets=exclude_subnets,
        public_key=public_key,
    )

    return private_key

def _add_node_core(
    *,
    state: State,
    node_id: str,
    user_id: str,
    iface_name: str,
    platform: Platform,
    tunnel_mode: TunnelMode,
    exclude_subnets: Optional[List[str]],
    public_key: str,
) -> None:
    # 1. basic validation
    if node_id in state.nodes and state.nodes[node_id].status == "active":
        raise ValueError(f"Node '{node_id}' already exists and is active")

    if not public_key:
        raise ValueError("Public key must be provided")

    # 2. interface must exist
    if iface_name not in state.interfaces:
        raise ValueError(f"Interface '{iface_name}' does not exist")

    iface = state.interfaces[iface_name]

    # 3. derive peer_id
    peer_id = _make_peer_id(node_id, iface_name)

    if peer_id in state.allocations.used_peer_ids:
        raise ValueError(f"Peer '{peer_id}' already exists")

    # 4. create or update node
    state.nodes[node_id] = Node(
        node_id=node_id,
        user_id=user_id,
        status="active",
    )

    # 5. allocate IPs
    assigned_ip_v4 = _allocate_ip_v4(state, iface)
    assigned_ip_v6 = None

    if iface.vpn_subnet_v6:
        assigned_ip_v6 = _allocate_ip_v6(state, iface)


    # 6. allowed_ips calculation depends on tunnel mode and exclusions
    allowed_ips = _compute_allowed_ips(
    tunnel_mode=tunnel_mode,
    iface=iface,
    exclude_subnets=exclude_subnets or [],
)


    # 7. create peer
    peer = Peer(
        peer_id=peer_id,
        node_id=node_id,
        iface_name=iface_name,
        server_id=iface.server_id,
        platform=platform,
        tunnel_mode=tunnel_mode,
        exclude_subnets=exclude_subnets or [],
        public_key=public_key,
        assigned_ip_v4=assigned_ip_v4,
        assigned_ip_v6=assigned_ip_v6,
        allowed_ips=allowed_ips,
        created_at=datetime.utcnow(),
    )

    # 8. register peer
    state.peers[peer_id] = peer
    state.allocations.used_peer_ids.add(peer_id)

def revoke_node(
    *,
    state: State,
    node_id: str,
    reason: str,
) -> None:
    if node_id not in state.nodes:
        raise ValueError(f"Node '{node_id}' does not exist")

    node = state.nodes[node_id]

    if node.status == "revoked":
        raise ValueError(f"Node '{node_id}' is already revoked")

    # find peers belonging to this node
    peer_ids = [
        peer_id
        for peer_id, peer in state.peers.items()
        if peer.node_id == node_id
    ]

    # remove peers
    for peer_id in peer_ids:
        peer = state.peers[peer_id]

        if peer.assigned_ip_v4:
            state.allocations.used_ips_v4.discard(peer.assigned_ip_v4)
        if peer.assigned_ip_v6:
            state.allocations.used_ips_v6.discard(peer.assigned_ip_v6)

        del state.peers[peer_id]
        state.allocations.used_peer_ids.discard(peer_id)


    # mark node revoked
    node.status = "revoked"
    state.revocations[node_id] = datetime.utcnow()
