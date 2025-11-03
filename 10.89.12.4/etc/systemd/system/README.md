`sudo systemctl daemon-reload`

`sudo systemctl enable tailscale-relay`

`sudo systemctl start tailscale-relay`

This ensures:
- tailscaled starts at boot
- Your NAS advertises itself as a relay automatically
- It restarts if it crashes
