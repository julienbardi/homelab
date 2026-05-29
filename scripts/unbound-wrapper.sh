#!/bin/sh
# UGREEN systemd ignores RuntimeDirectory and ExecStartPre.
# We must create /run/unbound manually *inside ExecStart*.
set -eu

mkdir -p /run/unbound
chown unbound:unbound /run/unbound
chmod 0750 /run/unbound

exec /usr/sbin/unbound -d -c /etc/unbound/unbound.conf
