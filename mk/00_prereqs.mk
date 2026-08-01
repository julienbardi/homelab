# mk/00_prereqs.mk — prereqs entry point
# ------------------------------------------------------------
# CONTRACT:
# - prereqs-* targets may mutate system state
# - *-verify targets never mutate state
# - installs must be idempotent
# - failures must be explicit and actionable
# ------------------------------------------------------------

include mk/prereqs-variables.mk
include mk/prereqs-network.mk
include mk/prereqs-system.mk
include mk/prereqs-tailscale.mk
include mk/prereqs-core.mk
