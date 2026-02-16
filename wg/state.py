# state.property
# in‑memory model
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set
from enum import Enum
from datetime import datetime

dns_servers=["10.89.12.1", "fd89:7a3b:42c0::1"]
v6_egress_capable=True

class Platform(Enum):
    ANDROID = "android"
    WINDOWS = "windows"
    MACOS = "macos"


class TunnelMode(Enum):
    SPLIT = "split"
    FULL = "full"

@dataclass
class Node:
    node_id: str
    user_id: str
    status: str  # "active" | "revoked"

@dataclass
class Interface:
    iface_name: str
    server_id: str
    listen_port: int
    vpn_subnet_v4: Optional[str]
    vpn_subnet_v6: Optional[str]
    lan_subnets: List[str]
    internet_access: bool
    ipv6_access: bool

@dataclass
class Server:
    server_id: str
    host: str
    interfaces: Set[str] = field(default_factory=set)

@dataclass
class Peer:
    peer_id: str
    node_id: str
    iface_name: str
    server_id: str
    platform: Platform
    tunnel_mode: TunnelMode
    exclude_subnets: List[str]
    public_key: str
    assigned_ip_v4: Optional[str]
    assigned_ip_v6: Optional[str]
    allowed_ips: List[str]
    created_at: datetime

@dataclass
class Allocations:
    used_ports: Set[int] = field(default_factory=set)
    used_peer_ids: Set[str] = field(default_factory=set)
    used_ips_v4: Set[str] = field(default_factory=set)
    used_ips_v6: Set[str] = field(default_factory=set)

@dataclass
class State:
    nodes: Dict[str, Node] = field(default_factory=dict)
    interfaces: Dict[str, Interface] = field(default_factory=dict)
    servers: Dict[str, Server] = field(default_factory=dict)
    peers: Dict[str, Peer] = field(default_factory=dict)
    allocations: Allocations = field(default_factory=Allocations)
    revocations: Dict[str, datetime] = field(default_factory=dict)
