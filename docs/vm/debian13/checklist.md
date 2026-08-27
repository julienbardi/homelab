# Debian 13 VM Creation Checklist (Proxmox) for debian13-xfce

01. Open https://10.89.12.4:8006
02. Log in to Proxmox
        - User name: root
        - Password (see Keepass)
        - Realm: Linux PAM standard authentication

03. Upload Debian ISO
    - Datacenter → pve → iso-tank
    - ISO Images → Download from URL
    - URL: [https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso](https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso)
    - File Name: debian-13.6.0-amd64-netinst.iso
    See https://www.debian.org/download
    - Hash algorithm: `SHA-512`
    - Checksum: `ce0eeee7b51fdcdbed1e5116668c1fee27e528767bdf488e5f115a67b225e5dfd0afca1d456aaa9408ceb6b8527521ff7b6b5d62fdbe6f8c5faaf8df56a96292`
    according to https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA512SUMS
    - Download
    - optional:  read https://www.debian.org/releases/stable/amd64/index.en.html

04. Create VM
    - Click: Create VM

05. General
    - Node: `pve`
    - VM ID: next free number after `200`:
    - Name: `debian13-xfce`
    - Add to HA: Disabled
    - Resource Pool: (empty)

06. OS
    - ISO Image: `debian-13.6.0-amd64-netinst.iso`
    - Type: `Linux`
    - Version: `7.x - 2.6 kernel`

07. System
    - Graphic Card: `SPICE`
    - Machine: `q35`
    - BIOS: `OVMF (UEFI)`
    - Add EFI Disk: Enabled
    - EFI Storage: `vmdata` - EFI storage should always live on your large, persistent disk, not on the small local-lvm thin pool.
    - SCSI Controller: `VirtIO SCSI single`
    - QEMU Agent: Enabled
    - Add TPM: No - irrelevant for Debian

08. Disks
    - Bus/Device: SCSI 0
    - Storage: `vmdata`
    - Disk Size (GiB): `32`
    - Cache: `Write back`
    - Discard: Enabled
    - IO thread: Enabled
    - SSD Emulation: Enabled
    - Read-only: Disabled
    - Backup: Enabled
    - Skip replication: Disabled
    - Async IO: `Default (io_uring)`

09. CPU
    - Sockets: `1`
    - Cores: `4`
    - Type: `host`
    - NUMA: Disabled (Only useful for >8 cores or multi-socket hosts)
    Extra CPU Flags
    - nested-virt: Off
    - all hv-* flags: Off
    - Leave `Default` for all other flags

10. Memory
    - Memory (MiB): `4096`
    - Ballooning Device: Disabled
    - Allow KSM: Enabled

11. Network
    - Bridge: `vmbr0`
    - Model: VirtIO (paravirtualized)
    - VLAN Tag: no VLAN
    - MAC address: auto
    - Firewall: disabled
    - Disconnect: Disabled
    - Rate limit (MB/s): unlimited
    - MTU: Same as bridge
    - Multiqueue: 4

12. Confirm
    - Review settings
    - Click Finish

13. Start VM
    - Select VM → Start
    - Open Console

14. Install Debian 13
    - Choose: Graphical Install
    - English
    - Select your location other > Europe > Switzerland
    - Configure locales: en_US.UTF-8
    - Keyboard: Swiss German
    - Hostname: `debian`
    - Domain name: (leave empty)
    - Root password: (leave empty)
    - Set up users and passwords: Full name for the new user: <fullname>
    - Username: first 5 letters (like on Windows) for convinience
    - Partitioning: Guided - use entire disk
    - Partition Disks: All files in one partition (recommended for new users)
    - Configure the package manager - scan extra installation media? No
    - Switzerland `mirror.iway.ch`
    - HTTP proxy: (leave empty)
    - Package usage survey: No
    - Software selection:
        - Debian desktop environment: Enabled
        - XFCE: Enabled
        - SSH server: Enabled
        - Standard system utilities: Enabled
        - Web server: Disabled
    - Finish installation

15. Inside Debian (post-install)
    - Install guest agent:
        sudo apt update
        sudo apt install qemu-guest-agent
        sudo systemctl start qemu-guest-agent
    Optionally verify:
        systemctl status qemu-guest-agent
    You should see Active: active (running)

    - Enable TRIM:
        sudo systemctl enable fstrim.timer
    - Add SPICE agent (optional: this gives clipboard + dynamic resolution)
        sudo apt install spice-vdagent

16. Shutdown VM
    - VM → Shutdown

17. Enable QEMU Guest Agent in Proxmox (if not already)
    - VM → Options → QEMU Guest Agent → Enabled

18. Start VM again
    - VM → Start

19. Install XRDP (Debian 13 + XFCE)

# 19.1 Install XRDP + Xorg backend
sudo apt update
sudo apt install xrdp xorgxrdp dbus-x11 polkitd
sudo systemctl enable --now xrdp

# 19.2 Create a clean .xsession (XRDP will execute this)
echo "xfce4-session" > ~/.xsession
chmod +x ~/.xsession

# 19.3 Replace Debian 13’s broken /etc/xrdp/startwm.sh
```bash
sudo tee /etc/xrdp/startwm.sh >/dev/null <<'EOF'
#!/bin/sh

# Load locale
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi

# Force XFCE session (Debian 13 fix)
export XDG_SESSION_TYPE=x11
export DESKTOP_SESSION=xfce
export XDG_SESSION_DESKTOP=xfce
export XDG_CURRENT_DESKTOP=XFCE

exec xfce4-session
EOF

sudo chmod +x /etc/xrdp/startwm.sh
```

# 19.4 Restart XRDP
```
sudo systemctl restart xrdp xrdp-sesman
```

# 19.5 Log out of local GUIsession
Log out of the local GUI session
# (Debian 13 cannot run two Xorg sessions for the same user)

# 19.6 Connect via RDP (Session type: Xorg)
If it fails, try to reboot the machine

# 20. Operator provisioning

## Operator Provisioning (BAS → sudo → SSH → XRDP)
```bash
# BAS: Base Account Setup (standard UNIX user)
sudo adduser leona

# Optional: elevate leona to operator (sudo privileges)
sudo usermod -aG sudo leona
```

## give leona SSH key‑based login
```bash
sudo install -d -m 700 -o leona -g leona /home/leona/.ssh
sudo install -m 600 -o leona -g leona /dev/null /home/leona/.ssh/authorized_keys
```

## Provision XRDP Session
```bash
echo "xfce4-session" | sudo tee /home/leona/.xsession >/dev/null
sudo chown leona:leona /home/leona/.xsession
sudo chmod 755 /home/leona/.xsession
```

# Allow you machine to access via SSH (example for julie)
Windows: ensure OpenSSH Client is installed (Settings → Optional Features)

1. locate your SSH public key
```powershell
cat $env:USERPROFILE\.ssh\id_ed25519.pub
```

2. copy your public key to the Debian VM using scp
This assumes that debian is the hostname of the machine has been configured in the DNS.


```powershell
scp $env:USERPROFILE\.ssh\id_ed25519.pub julie@<VM-IP>:/home/julie/
```

Troubleshooting: to find the IP address of the VM, run: `hostname -I`

3. On Debian: install the key properly

```bash
sudo install -d -m 700 -o julie -g julie /home/julie/.ssh
sudo install -m 600 -o julie -g julie /home/julie/id_ed25519.pub /home/julie/.ssh/authorized_keys
```

4. Test SSH login from Windows
```powershell
ssh julie@debian
```

## 21. Graphical Scaling (XFCE + XRDP) to 200%

### 21.1 Enable custom DPI (200%)
Open the XFCE appearance settings:

```
xfce4-appearance-settings
```

Then:

- Go to **Fonts**
- Enable **Custom DPI**
- Set DPI to **192** (equivalent to 200%)

This fixes tiny fonts in menus, windows, dialogs, Thunar, and XFCE settings.

---

### 21.2 Adjust XFCE panel size
Open panel preferences:

```
xfce4-panel --preferences
```

Then set:

- **Panel → Row Size → 36–40**

This prevents the top panel from staying tiny after DPI scaling.

---

### 21.3 Force system-wide DPI (important for XRDP)
Create the fontconfig directory:

```
mkdir -p ~/.config/fontconfig
nano ~/.config/fontconfig/fonts.conf
```

Insert:

```xml
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <edit name="dpi" mode="assign">
      <double>192</double>
    </edit>
  </match>
</fontconfig>
```

This ensures consistent scaling for older GTK apps and XRDP sessions.

---

### 21.4 Restart the XFCE panel
```
xfce4-panel -r
```

---

### 21.5 Ensure XRDP uses Xorg session
When connecting from Windows RDP:

- Select **Session type: Xorg**

XRDP scaling does not work correctly under Xvnc.

---

### 21.6 (Optional) Increase icon size
Open:

```
xfce4-settings-manager
```

Then:

- **Icons → Default → Size 32 or 48**

---

### Result
With:

- Custom DPI = 192
- Panel row size = 36–40
- Fontconfig DPI = 192
- XRDP Xorg session

XFCE becomes fully readable at **200% scaling**, including menus, windows, Thunar, dialogs, and RDP sessions.
