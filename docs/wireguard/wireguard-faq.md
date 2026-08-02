# WireGuard FAQ
Homelab Network — Router + NAS Unified Control Plane

This FAQ provides quick answers to common questions about the WireGuard control plane. It is designed for operators who need fast guidance without reading the full architecture or debugging documents.

## 1. General Questions

# Q: Where is the authoritative WireGuard configuration stored?
A: In runtime under /var/lib/homelab/wireguard. The repo only contains templates and secrets.

# Q: Where are private keys stored?
A: In SOPS-encrypted YAML files under wireguard/secrets/*.yaml. Router private key lives in NVRAM.

# Q: Where do I edit topology?
A: Edit TSV files under wireguard/input/*.tsv.

# Q: Where do I edit secrets?
A: Edit SOPS files under wireguard/secrets/*.yaml.

# Q: How do I regenerate configs?
A: make wg-generate

# Q: How do I apply configs?
A: make wg-install

# Q: How do I bring WireGuard up?
A: make wg-up

# Q: How do I restart WireGuard?
A: make wg-restart

# Q: How do I check status?
A: make wg-status

## 2. Router Questions

# Q: How do I check if wgs1 is running?
A: ssh router "wg show wgs1"

# Q: How do I check router identity?
A: ssh router "nvram get wgs1_priv"
   ssh router "nvram get wgs1_pub"

# Q: How do I fix missing router identity?
A: make router-bootstrap-wg-keys

# Q: How do I reinstall router configs?
A: make wg-install-router

# Q: How do I bring router WG up?
A: make wg-up-router

# Q: How do I check router IPv6?
A: make wg-router-ipv6-probe

## 3. NAS Questions

# Q: How do I check if wg7 is running?
A: sudo wg show wg7

# Q: How do I reinstall NAS configs?
A: make wg-install-nas

# Q: How do I bring NAS WG up?
A: make wg-up-nas

# Q: How do I validate wg7?
A: make wg7-validate

# Q: How do I check NAS IPv6?
A: sudo ip -6 addr show dev eth0

# Q: How do I check NAT66?
A: sudo nft list chain ip6 homelab_nat6 postrouting

## 4. IPv6 / NAT66 Questions

# Q: Why does IPv6 matter for WireGuard?
A: wg7 uses IPv6 egress via NAT66 on NAS.

# Q: How do I check IPv6 egress?
A: curl -6 https://ifconfig.io

# Q: How do I check IPv6 default route?
A: ip -6 route show | grep default

# Q: How do I fix missing NAT66?
A: make nft-apply
   make nft-confirm

## 5. Drift Questions

# Q: What is drift?
A: When runtime state differs from generated configs or TSVs.

# Q: How do I detect drift?
A: Dirty stamps under /var/lib/homelab/wireguard/*.stamp.

# Q: How do I fix drift?
A: make wg-install-router
   make wg-install-nas

# Q: What causes drift?
A: Topology changes, secrets changes, kernel state changes, NVRAM resets.

## 6. Secrets Questions

# Q: How do I rotate keys?
A: Edit SOPS files → make wg-generate → make wg-install → make wg-restart.

# Q: Where is router private key stored?
A: In NVRAM (wgs1_priv).

# Q: Where are NAS private keys stored?
A: In SOPS-encrypted YAML files.

# Q: Are secrets ever written to disk unencrypted?
A: No. They are decrypted only in RAM during generation.

## 7. Emergency Questions

# Q: Router WireGuard is broken — what do I do?
A: make wg-down-router
   make router-bootstrap-wg-keys
   make wg-install-router
   make wg-up-router

# Q: NAS WireGuard is broken — what do I do?
A: make wg-down-nas
   make wg-install-nas
   make wg-up-nas

# Q: Everything is broken — what do I do?
A: make wg-down
   make wg-install
   make wg-up

## 8. Operator Workflow Questions

# Q: What is the daily workflow?
A: git pull → make wg-generate → make wg-install → make wg-up → validate.

# Q: What is the topology change workflow?
A: Edit TSV → commit → push → pull → generate → install → restart → validate.

# Q: What is the secrets change workflow?
A: Edit SOPS → commit → push → pull → generate → install → restart.

## 9. Misc Questions

# Q: Can I manually edit configs under /var/lib/homelab/wireguard?
A: No. Never.

# Q: Can I manually edit router NVRAM?
A: No. Only via router-bootstrap-wg-keys.

# Q: Can I manually edit NAS configs?
A: No. Only via wg-install-nas.

# Q: Can I manually run wgctl.sh?
A: No. Always use Make targets.

## 10. Summary

This FAQ provides quick answers for:

- router issues
- NAS issues
- IPv6/NAT66 issues
- drift issues
- secrets issues
- emergency recovery
- operator workflows

It is the fastest reference for day-to-day WireGuard operations.
