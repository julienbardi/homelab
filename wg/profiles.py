from dataclasses import dataclass
from typing import Dict, Literal

TunnelMode = Literal["split", "full"]

@dataclass(frozen=True)
class ProfileIntent:
	tunnel_mode: TunnelMode
	lan_access: int   # 0|1
	egress_v4: int    # 0|1
	egress_v6: int    # 0|1

PROFILES: Dict[str, ProfileIntent] = {
	# Fill these with your real set; examples:
	"lan_v4_split": ProfileIntent(tunnel_mode="split", lan_access=1, egress_v4=0, egress_v6=0),
	"egress_v4_full": ProfileIntent(tunnel_mode="full", lan_access=0, egress_v4=1, egress_v6=0),
	"lan+egress_v6_full": ProfileIntent(tunnel_mode="full", lan_access=1, egress_v4=0, egress_v6=1),
}
