# 🌐 WireGuard VPN Setup on NAS (10.89.12.4) with Family Onboarding
## 1. Install and Verify WireGuard on NAS
Install WireGuard tools:
```
sudo apt update
sudo apt install wireguard
```

Check kernel version (WireGuard is built‑in since Linux 5.6):

```
uname -r
```

👉 You already have 6.12.30+, which is very modern.

Check WireGuard tools version:

```
wg --version
```
Even if it shows v1.0.20210914, that’s fine — the kernel provides the VPN engine.

## 2. Generate Keys
On the NAS (server)

```
umask 077
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
chmod 600 /etc/wireguard/server_private.key
chmod 644 /etc/wireguard/server_public.key
chown root:root /etc/wireguard/server_*.key
```

- server_private.key → keep secret on NAS
- server_public.key → share with clients


On each client (two models)

Model A: Client generates keys (most secure)

Windows: WireGuard app → Add empty tunnel → keys auto‑generated.

Android: WireGuard app → + → Create from scratch → keys auto‑generated.

Linux:

```
umask 077
wg genkey | tee ~/client_private.key | wg pubkey > ~/client_public.key
```

They send you only the public key (via email, Signal, Incamail, etc.).

Model B: Server generates keys (most convenient)

On NAS:

```
umask 077
wg genkey | tee clientX_private.key | wg pubkey > clientX_public.key
```

Create a full client config (clientX.conf) with both keys.

Export as QR code for mobile:

```
qrencode -t ansiutf8 -r clientX.conf
```
Family member scans QR code in WireGuard app or imports .conf file.

Note: You temporarily know their private key, so deliver securely (encrypted email, password‑protected archive, or in person).

## 3. Configure the NAS (server)
File: `/etc/wireguard/wg0.conf`:
```
ini
[Interface]
Address = 10.4.0.1/24
ListenPort = 51420
PrivateKey = <server_private_key>

# Example: Client1 (Windows)
[Peer]
PublicKey = <Client1_public_key>
AllowedIPs = 10.4.0.0/32

# Example: Client2 (Android)
[Peer]
PublicKey = <Client2_public_key>
AllowedIPs = 10.4.0.0/32

# Example: Client3 (Linux)
[Peer]
PublicKey = <Client3_public_key>
AllowedIPs = 10.4.0.0/32
```

Enable routing:
```
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

## 4. Configure Clients
Windows (Client2)
```
ini
[Interface]
Address = 10.4.0.2/24
PrivateKey = <Client2_private_key>
MTU = 1420

[Peer]
PublicKey = <server_public_key>
AllowedIPs = 10.89.12.0/24
Endpoint = <your_public_hostname>:51420
PersistentKeepalive = 25
```



## 5. Add Static Route on Router (RT‑AX86U)
In router UI (LAN → Route):

Network/Host IP (Destination): `10.4.0.0`
Netmask: `255.255.255.0`
Gateway: `10.89.12.4` (NAS)
Metric: `1`
Interface: `LAN`


This ensures LAN devices reply directly to VPN clients.

## 6. Start Services
On NAS:

```
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
```

On Linux client:

```
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
```

On Windows/Android: toggle tunnel ON in the app.

## 7. Family Onboarding Kit (repeatable process)
For each family member:

Decide if they generate keys (Model A) or you generate configs (Model B).

Assign them a VPN IP in 10.4.0.0/24 (e.g. 10.4.0.5, 10.4.0.6, …).

Add their public key to NAS config under [Peer].

Deliver their config securely:

Windows/Linux: send .conf file via encrypted email or password‑protected archive.

Android/iOS: generate QR code and let them scan it.

Restart NAS WireGuard service:

```
sudo systemctl restart wg-quick@wg0
```

## 8. Revoking a Client

8.1. Remove its [Peer] block from NAS config.

8.2. Restart:
```
sudo systemctl restart wg-quick@wg0
```
That client can no longer connect.

## ✅ Final Overview
- VPN subnet: 10.4.0.0/24
- NAS (server): 10.4.0.1
- Clients: 10.4.0.x (family members)
- Router static route: 10.4.0.0/24 → 10.89.12.4
- Family onboarding kit: repeatable process with either client‑generated keys or server‑generated configs + QR codes.
- Result: Remote family members can connect securely and reach your LAN at full speed, with clean routing and no NAT.
