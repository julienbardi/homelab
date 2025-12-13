#!/bin/bash
# Script: ipv6_route_fix.sh
# Checks for and deletes the problematic static ULA default route forced by UGOS.
# to deploy use 
#     sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/ipv6_route_fix.sh /usr/local/bin/ipv6_route_fix.sh

# Define the problematic route string to check for
BAD_ROUTE="default via fd10:8912:0:c::1 dev bridge0"
GATEWAY="fd10:8912:0:c::1"
INTERFACE="bridge0"
LOG_FILE="/var/log/ipv6_route_fix.log"

# Check if the route is currently in the routing table (Exit code 0 means found)
if ip -6 route show | grep -q "${BAD_ROUTE}"; then
    echo "$(date) ⚠️ Found problematic IPv6 default route. Deleting it..." >> "${LOG_FILE}"

    # Execute the deletion command and test it directly
    if sudo ip -6 route del default via "${GATEWAY}" dev "${INTERFACE}"; then
        echo "$(date) ✅ Problematic route deleted successfully." >> "${LOG_FILE}"
    else
        echo "$(date) ❌ ERROR: Failed to delete the route." >> "${LOG_FILE}"
    fi
else
    echo "$(date) ✅ Problematic IPv6 default route is not present." >> "${LOG_FILE}"
fi

# --- Check for the CORRECT default route ---
if ! ip -6 route show | grep -q "default via fe80::127c:61ff:fe42:c2c0"; then
    echo "$(date) ⚠️ Missing correct default IPv6 route. Adding it..." >> "${LOG_FILE}"

    # Add the correct route and test the command directly
    if sudo ip -6 route add default via fe80::127c:61ff:fe42:c2c0 dev bridge0; then
        echo "$(date) ✅ Correct default route added successfully." >> "${LOG_FILE}"
    else
        echo "$(date) ❌ ERROR: Failed to add correct default route." >> "${LOG_FILE}"
    fi
fi

# OPTIONAL: You may want to ensure the firewall rules are loaded here too, 
# especially if UGOS runs its own firewall after your boot scripts.
# sudo /usr/local/bin/firewall.sh >> "${LOG_FILE}" 2>&1
