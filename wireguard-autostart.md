# Deploying a Custom WireGuard Build on a NAS with Systemd Autostart
Author: Julie Date: November 2025 Status: under construction

##  Introduction
WireGuard has become the de‑facto standard for secure, performant VPN tunnels. Many NAS systems ship with older versions of wireguard-tools, which can lead to syntax mismatches or missing features. This article describes how to build and install the latest WireGuard tools in a clean, isolated way, and configure systemd to ensure tunnels start automatically at boot — without overwriting vendor‑managed binaries.

##  Step 1: Prepare a Build Workspace
Keep source code separate from system directories:

bash
mkdir -p ~/src
cd ~/src
git clone https://git.zx2c4.com/wireguard-tools
cd wireguard-tools/src
##  Step 2: Build the Tools
Compile the binaries locally:

bash
make
This produces fresh wg and wg-quick binaries in the build directory.

##  Step 3: Install into a Custom Location
Install into /opt/wireguard-latest so your build is clearly separated from the NAS vendor’s files:

bash
sudo make PREFIX=/opt/wireguard-latest install
Resulting binaries:

/opt/wireguard-latest/bin/wg

/opt/wireguard-latest/bin/wg-quick

##  Step 4: Create WireGuard Configurations (Later)
Configuration files (/etc/wireguard/wg0.conf, wg1.conf, …) define interfaces, keys, endpoints, and subnets. For now, you can postpone this step until you regenerate secure keys and finalize your subnet conventions.

##  Step 5: Override the Systemd Unit
Systemd’s wg-quick@.service template normally calls /usr/bin/wg-quick. Override it to use your custom binary:

bash
sudo systemctl edit wg-quick@.service
Add:

Code
[Service]
ExecStart=
ExecStart=/opt/wireguard-latest/bin/wg-quick up %i
ExecStop=
ExecStop=/opt/wireguard-latest/bin/wg-quick down %i
This ensures systemd always uses your build.

Step 6: Enable Autostart
Reload systemd and enable the service for your chosen interface (e.g. wg0):

bash
sudo systemctl daemon-reexec
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
Step 7: Verify
Check service status and interface details:

bash
systemctl status wg-quick@wg0
wg show
ip addr show wg0
After reboot, the tunnel will come up automatically using your custom binaries.

Why This Approach Works
Survives reboot: systemd ensures tunnels are always brought up.

Preserves vendor binaries: UGOS’s /usr/bin/wg remains untouched.

Precise control: only the service is redirected; your shell can still use the vendor version if desired.

Easy rollback: remove the override with sudo systemctl revert wg-quick@.service.

##  Conclusion
By installing WireGuard into /opt/wireguard-latest and overriding the systemd unit, you gain the benefits of the latest features while keeping your NAS system stable and vendor‑compliant. This workflow is robust, reversible, and ready for production once your configuration files are finalized.
