from dataclasses import dataclass

@dataclass(frozen=True)
class PeerRequest:
    node: str
    user: str
    iface: str
    profile: str
    public_key: str | None  # None means “needs keygen”
    revoked: bool = False
