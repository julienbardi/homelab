# 🌐 WireGuard VPN Setup on NAS (10.89.12.4) with Family Onboarding

## 🔧 Interfaces
- `wg-lan`: LAN access only
- `wg-inet`: Full VPN tunnel

## 🧩 Profiles
| Profile     | Access         | DNS                 | IPv6 | Expiry |
|-------------|----------------|---------------------|------|--------|
| lan-only    | LAN only       | Internal only       | Optional | No     |
| lan-inet    | LAN + Internet | Internal + public   | Yes  | No     |
| inet-only   | Internet only  | Internal + public   | Yes  | 1 year |

### 🚀 Onboarding
```bash
sudo add-wireguard-client.sh <interface> <name> <ip> <profile> <email>
```
### 🧹 Cleanup
```bash
sudo wg-clean-expired.sh
```
### 📊 Dashboard
```bash
sudo wg-dashboard.sh
```
### 📁 Metadata
Each client has:
- meta.txt: name, email, profile, expiry
- client.conf: WireGuard config
- client.pub, client.key: keys

## 🧠 3. Script That Mimics `wg` to Manage Users

Your onboarding script already uses:
```bash
wg set <interface> peer <pubkey> allowed-ips <ip>
```
Your cleanup script uses:
```bash
wg set <interface> peer <pubkey> remove
```
This is exactly how wg works — your scripts are native-compatible.

📊 4. Supercharged wg show → Dashboard
Your dashboard script:

Uses wg show <interface> dump

Matches public keys to metadata

Displays:

- 👤 Name
- 📧 Email
- 🔗 Interface
- 🔑 Public Key
- 🌐 IP
- 📦 Profile
- 📡 Last Handshake
- ⬇️ RX / ⬆️ TX
- 📅 Expiry

It’s a supercharged version of wg show, with full visibility.

## 1. One-Time Setup Steps

### 🔧 Install and Verify WireGuard on NAS
Install WireGuard and dependencies:
```
sudo apt update
sudo apt install wireguard qrencode
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
File: `/etc/wireguard/wg-lan.conf`:
File: `/etc/wireguard/wg-inet.conf`:

```
ini
[Interface]
Address = 10.4.0.1/24,fd42:42:42::1/64
ListenPort = 51420
PrivateKey = <server_private_key>
MTU = 1420
```
Note: client will append blocks like 

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


### 🔐 Enable IP forwarding:
```
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```
## 4. 📁 Create client folders
```
sudo mkdir -p /etc/wireguard/clients/wg-lan
sudo mkdir -p /etc/wireguard/clients/wg-inet
```

## 5. 🧩 Install scripts
- /usr/local/bin/add-wireguard-client.sh → onboarding with profile + expiry
- /usr/local/bin/wg-clean-expired.sh → cleanup expired peers
- /usr/local/bin/wg-dashboard.sh → pretty CSV-compatible dashboard

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
