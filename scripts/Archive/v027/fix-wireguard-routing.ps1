param(
  [switch]$Helper
)

if ($Helper) {
  Write-Host @"
fix-wireguard-routing.ps1
-------------------------
Use this script only for IPv6-enabled WireGuard interfaces (wg4, wg5, wg6, wg7).

Purpose:
  Ensure Windows routes LAN/IPv6 traffic via the WireGuard tunnel
  instead of preferring local LAN IPv6.

When to run:
  • Run this script AFTER connecting to an IPv6-enabled WireGuard profile (wg4–wg7).
  • You may re-run it WHILE the VPN is active if routes get reset (e.g. after sleep/wake).
  • Do NOT run it BEFORE connecting (the WireGuard interface does not yet exist).
  • No need to run it AFTER disconnecting (routes are removed automatically).

Usage:
  .\fix-wireguard-routing.ps1
  .\fix-wireguard-routing.ps1 -Helper   # show this help
"@
  exit
}

$targetPrefix = "10.89.12.0/24"
$nextHop = "10.4.0.1"
$logTag = "[WireGuardRouteFix]"

Write-Host "$logTag Checking existing routes for $targetPrefix..."

# Remove conflicting routes
$existingRoutes = Get-NetRoute | Where-Object { $_.DestinationPrefix -eq $targetPrefix }
foreach ($route in $existingRoutes) {
    if ($route.NextHop -ne $nextHop) {
        Write-Host "$logTag Removing route on interface $($route.InterfaceIndex)..."
        Remove-NetRoute -DestinationPrefix $targetPrefix -InterfaceIndex $route.InterfaceIndex -Confirm:$false
    } else {
        Write-Host "$logTag Valid route already exists via $nextHop on interface $($route.InterfaceIndex)."
        return
    }
}

# Add correct route via WireGuard
$wgInterface = Get-NetIPInterface | Where-Object { $_.InterfaceAlias -like "*WireGuard*" } | Sort-Object InterfaceMetric | Select-Object -First 1
if ($wgInterface) {
    Write-Host "$logTag Adding route via WireGuard (InterfaceIndex $($wgInterface.InterfaceIndex))..."
    New-NetRoute -DestinationPrefix $targetPrefix -InterfaceIndex $wgInterface.InterfaceIndex -NextHop $nextHop -RouteMetric 10
    Write-Host "$logTag Route added successfully."
} else {
    Write-Host "$logTag ERROR: WireGuard interface not found."
}
