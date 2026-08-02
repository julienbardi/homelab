# WireGuard TSV Model
Homelab Network — Router + NAS Unified Control Plane

This document defines the schema, contracts, and validation rules for the TSV files that describe WireGuard topology. These TSVs are the authoritative templates used by the control plane to generate configs.

## 1. Purpose of the TSV Model

The TSV files under wireguard/input/*.tsv define:

- interface inventory
- host roles (router vs NAS)
- peer assignments
- subnets and addressing
- generation metadata

TSVs contain no secrets. They are safe to version and safe for multi-operator workflows.

## 2. File: wg-interfaces.tsv

This is the primary TSV file. It defines all WireGuard interfaces and their roles.

# Columns

1. interface
2. role
3. description
4. ipv4_subnet
5. ipv6_subnet
6. generation_id

# Column Contracts

# interface
- Must be a valid WireGuard interface name (e.g., wgs1, wg7).
- Must not contain spaces.
- Must be unique across the file.
- Must not be commented unless the entire row is disabled.

# role
- Must be either router or nas.
- router = interface lives on the Asus router
- nas = interface lives on the NAS
- Determines which control-plane module handles the interface.

# description
- Free-form text.
- Optional.
- Used only for operator clarity.

# ipv4_subnet
- Must be a valid CIDR (e.g., 10.89.7.0/24).
- Must not overlap with other WG subnets.
- Must not overlap with Docker subnets (control plane checks this).
- Required for both router and NAS roles.

# ipv6_subnet
- Must be a valid IPv6 prefix (e.g., fd00:7::/64).
- Required for NAS interfaces.
- Optional for router interfaces (router may not serve IPv6 on WG).

# generation_id
- Integer.
- Incremented when topology changes.
- Used for drift detection.
- Must be monotonically increasing.

# Example Row (with # instead of #)

wgs1    router    main router server    10.89.1.0/24    fd00:1::/64    42

## 3. File: wg-peers.tsv (optional)

If present, this file defines peer assignments.

# Columns

1. interface
2. peer_name
3. peer_ipv4
4. peer_ipv6
5. allowed_ips
6. endpoint
7. persistent_keepalive

# Column Contracts

# interface
- Must match an interface defined in wg-interfaces.tsv.

# peer_name
- Free-form identifier.
- Must be unique per interface.

# peer_ipv4
- Must be inside the interface’s ipv4_subnet.

# peer_ipv6
- Must be inside the interface’s ipv6_subnet.

# allowed_ips
- Comma-separated list of CIDRs.
- Must not conflict with other peers.

# endpoint
- Optional.
- Required for remote peers.

# persistent_keepalive
- Optional.
- Integer seconds.

## 4. Validation Rules

The control plane enforces:

# Rule 1 — No duplicate interfaces
Each interface name must be unique.

# Rule 2 — No overlapping subnets
ipv4_subnet and ipv6_subnet must not overlap with each other or Docker.

# Rule 3 — Role must be router or nas
No other values allowed.

# Rule 4 — Subnets must be valid CIDRs
Invalid CIDRs abort generation.

# Rule 5 — generation_id must be integer
Used for drift detection.

# Rule 6 — Peer IPs must be inside interface subnets
Out-of-range IPs abort generation.

# Rule 7 — No commented partial rows
Rows starting with # or # are ignored entirely.

## 5. Dynamic MK Outputs

The TSVs produce two dynamic MK files:

# wg-subnets.mk
Contains subnet definitions for router and NAS.

# wg-interfaces.mk
Contains WG_INTERFACES_NAS := wg7 wg8 ...

These files are included into the Make DAG.

## 6. Multi-Operator Safety

TSVs are versioned in Git.
Operators modify TSVs, commit, push, and pull.
Runtime state is never edited manually.

Dirty stamps ensure safe convergence:

wg_router_dirty.stamp
wg_nas_dirty.stamp

## 7. Editing Workflow

# Step 1 — Edit TSV
Modify wireguard/input/*.tsv.

# Step 2 — Commit
git commit -am "Update WG topology"

# Step 3 — Push
git push

# Step 4 — Pull on homelab host
git pull

# Step 5 — Regenerate
make wg-generate

# Step 6 — Install
make wg-install

# Step 7 — Restart
make wg-restart

## 8. Summary

The TSV model defines:

- interface inventory
- roles
- subnets
- peer assignments
- generation metadata

It is the authoritative template for WireGuard topology and is safe for multi-operator workflows.
