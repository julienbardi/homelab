# finalize.py

from dataclasses import dataclass
from typing import Dict
from state import State, Peer, Interface, Server

@dataclass(frozen=True)
class FrozenState:
    servers: Dict[str, Server]
    interfaces: Dict[str, Interface]
    peers: Dict[str, Peer]

def finalize(state: State) -> FrozenState:
    _validate_state(state)
    return FrozenState(
        servers=dict(state.servers),
        interfaces=dict(state.interfaces),
        peers=dict(state.peers),
    )

def _validate_state(state: State) -> None:
    # Every peer must reference a valid interface and server
    for peer in state.peers.values():
        if peer.iface_name not in state.interfaces:
            raise ValueError(f"Peer {peer.peer_id} references unknown interface")

        iface = state.interfaces[peer.iface_name]

        if iface.server_id not in state.servers:
            raise ValueError(f"Interface {iface.iface_name} references unknown server")

        if not peer.allowed_ips:
            raise ValueError(f"Peer {peer.peer_id} has empty AllowedIPs")

        if not peer.public_key:
            raise ValueError(f"Peer {peer.peer_id} has no public key")
