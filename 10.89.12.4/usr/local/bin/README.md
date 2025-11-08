
Prerequisites for firewall-simple-wireguard.sh

Run this to check for the non‑legacy tools (one command; paste the output):

for b in iptables iptables-restore iptables-save ip6tables ip6tables-restore ip6tables-save ss ping; do
  if command -v "$b" >/dev/null 2>&1; then
    echo "OK:      $b -> $(command -v $b)"
  else
    echo "MISSING: $b"
  fi
done

MISSING: iptables 
MISSING: iptables-restore
MISSING: iptables-save
MISSING: ip6tables
MISSING: ip6tables-restore
MISSING: ip6tables-save
OK: ss -> /usr/bin/ss
OK: ping -> /usr/bin/ping

sudo apt install -y iptables

julie@nas:~/homelab/10.89.12.4/usr/local/bin$ sudo apt install -y iptables
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
iptables is already the newest version (1.8.9-2).
0 upgraded, 0 newly installed, 0 to remove and 192 not upgraded.

Run this to check for the iptables binaries as root (paste the output here):
for b in /sbin/iptables /sbin/iptables-restore /sbin/iptables-save /sbin/ip6tables /sbin/ip6tables-restore /sbin/ip6tables-save /usr/sbin/iptables* /usr/sbin/ip6tables*; do
  if [[ -e $b ]]; then ls -l "$b"; else echo "NOTFOUND: $b"; fi
done
