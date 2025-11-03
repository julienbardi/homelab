`sudo systemctl daemon-reload`

`sudo systemctl enable tailscale-relay`

`sudo systemctl start tailscale-relay`

This ensures:
- tailscaled starts at boot
- Your NAS advertises itself as a relay automatically
- It restarts if it crashes



If you prefer to build natively:

Install build tools (via Entware or your NAS’s package manager):

bash
opkg install golang git make
(If Entware isn’t installed, you’ll need to enable it first.)

Clone the Tailscale repo:

bash
git clone https://github.com/tailscale/tailscale.git
cd tailscale
Switch to the latest beta branch:

bash
git checkout unstable
Build:

bash
make
This produces tailscale and tailscaled binaries in ./cmd/tailscale and ./cmd/tailscaled.

Install: Copy them into /usr/local/bin or /opt/bin:

bash
cp ./cmd/tailscale/tailscale /opt/bin/
cp ./cmd/tailscaled/tailscaled /opt/bin/
Run:

bash
sudo tailscaled --state=/opt/tailscale/tailscaled.state &
sudo tailscale up --advertise-relay
