#!/bin/bash
# ============================================================
# aliases.sh
# ------------------------------------------------------------
# Supporting script: shell aliases for subnet router operations
# Responsibilities:
#   - router-logs: tail live logs of subnet-router.service
#   - router-deploy: copy edited setup-subnet-router.sh and restart service
# ============================================================

# --- Tail live logs ---
alias router-logs='journalctl -fu subnet-router.service'

# --- Deploy updated script ---
alias router-deploy="cp ~/setup-subnet-router.sh /usr/local/bin/setup-subnet-router.sh && systemctl restart subnet-router.service"

