# --------------------------------------------------------------------
# mk/40_wireguard.mk — WireGuard Control Plane (Orchestrator)
# --------------------------------------------------------------------
# This file now only includes the structured modules.
# All logic remains exactly as before, split into clean layers.
# --------------------------------------------------------------------

include $(REPO_ROOT)/mk/wireguard/10_env.mk
include $(REPO_ROOT)/mk/wireguard/20_inputs.mk
include $(REPO_ROOT)/mk/wireguard/30_generate.mk
include $(REPO_ROOT)/mk/wireguard/40_router.mk
include $(REPO_ROOT)/mk/wireguard/50_nas.mk
include $(REPO_ROOT)/mk/wireguard/60_lifecycle.mk
