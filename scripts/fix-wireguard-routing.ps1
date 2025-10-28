# fix-wireguard-routing.ps1
$targetPrefix = "192.168.50.0/24"
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
