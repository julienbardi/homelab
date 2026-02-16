# render\server.py

from typing import List
from finalize import FrozenState


def render_server_configs(frozen: FrozenState) -> dict[str, str]:
    """
    Returns a mapping:
        server_id -> full WireGuard config text
    """
    configs = {}

    for server_id in frozen.servers:
        configs[server_id] = _render_single_server(server_id, frozen)

    return configs


def _render_single_server(server_id: str, frozen: FrozenState) -> str:
    lines: List[str] = []

    server = frozen.servers[server_id]

    for iface_name in server.interfaces:
        iface = frozen.interfaces[iface_name]

        lines.extend(_render_interface_block(iface))
        lines.append("")

        for peer in frozen.peers.values():
            if peer.iface_name == iface_name:
                lines.extend(_render_peer_block(peer))
                lines.append("")

    return "\n".join(lines).strip()


def _render_interface_block(iface) -> List[str]:
    lines = [
        "[Interface]",
        f"ListenPort = {iface.listen_port}",
    ]

    if iface.vpn_subnet_v4:
        lines.append(f"Address = {iface.vpn_subnet_v4}")
    if iface.vpn_subnet_v6:
        lines.append(f"Address = {iface.vpn_subnet_v6}")

    return lines
