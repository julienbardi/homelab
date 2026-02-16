from typing import Dict, List
from finalize import FrozenState


def render_client_configs(
    frozen: FrozenState,
    *,
    interface_public_keys: Dict[str, str],
) -> Dict[str, str]:
    """
    Returns:
        peer_id -> client WireGuard config text

    interface_public_keys:
        iface_name -> server public key for that interface
    """
    configs: Dict[str, str] = {}

    for peer_id, peer in frozen.peers.items():
        iface = frozen.interfaces[peer.iface_name]
        server = frozen.servers[iface.server_id]

        if iface.iface_name not in interface_public_keys:
            raise ValueError(
                f"Missing public key for interface '{iface.iface_name}' "
                f"(needed for peer '{peer_id}')"
            )

        server_public_key = interface_public_keys[iface.iface_name]
        endpoint = f"{server.host}:{iface.listen_port}"

        configs[peer_id] = _render_single_client(
            peer=peer,
            endpoint=endpoint,
            server_public_key=server_public_key,
        )

    return configs


def _render_single_client(
    *,
    peer,
    endpoint: str,
    server_public_key: str,
) -> str:
    lines: List[str] = []

    lines.extend(_render_client_interface_block(peer))
    lines.append("")
    lines.extend(_render_client_peer_block(peer, endpoint, server_public_key))

    return "\n".join(lines).strip()


def _render_client_interface_block(peer) -> List[str]:
    lines = ["[Interface]"]

    addresses: List[str] = []

    if peer.assigned_ip_v4:
        addresses.append(f"{peer.assigned_ip_v4}/32")
    if peer.assigned_ip_v6:
        addresses.append(f"{peer.assigned_ip_v6}/128")

    if not addresses:
        raise ValueError(f"Peer '{peer.peer_id}' has no assigned IPs")

    for addr in addresses:
        lines.append(f"Address = {addr}")

    # PrivateKey is intentionally NOT emitted here.
    # It is provided to the client out-of-band.
    return lines


def _render_client_peer_block(
    peer,
    endpoint: str,
    server_public_key: str,
) -> List[str]:
    return [
        "[Peer]",
        f"PublicKey = {server_public_key}",
        f"Endpoint = {endpoint}",
        f"AllowedIPs = {', '.join(peer.allowed_ips)}",
        "PersistentKeepalive = 25",
    ]
