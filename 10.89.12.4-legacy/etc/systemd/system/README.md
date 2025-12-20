`sudo systemctl daemon-reload`

`sudo systemctl enable tailscale-relay`

`sudo systemctl start tailscale-relay`

This ensures:
- tailscaled starts at boot
- Your NAS advertises itself as a relay automatically
- It restarts if it crashes



If you prefer to build natively:

Step 1: Install build tools:
sudo apt update
sudo apt install -y golang git make


Step 2: Clone the Tailscale repo:
git clone https://github.com/tailscale/tailscale.git
cd tailscale
git checkout main
git pull

Step 3: Build the daemon (tailscaled):
cd ~/tailscale
go build -o tailscaled ./cmd/tailscaled

Step 4: Build the CLI (tailscale):
go build -o tailscale ./cmd/tailscale

Step 5: Copy them into your PATH:
sudo cp tailscaled /usr/local/bin/
sudo cp tailscale /usr/local/bin/

Step 6: verify by checking version
tailscaled --version
tailscale version

Step 7: Run the daemon:
sudo tailscaled --state=/var/lib/tailscale/tailscaled.state &

Step 8: Bring it up as a relay (requires v1.92+):
sudo tailscale up --advertise-relay
