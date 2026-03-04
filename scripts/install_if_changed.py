#!/usr/bin/env python3
"""
install_if_changed.py — DEPRECATED compatibility wrapper

This script is deprecated.
Use install_file_if_changed.sh instead.

This wrapper exists only for backward compatibility and will be removed.
"""

import os
import sys
import argparse

def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-q", "--quiet", action="store_true")
    parser.add_argument("-n", "--dry-run", action="store_true")
    parser.add_argument("--ssh-port")
    parser.add_argument("src")
    parser.add_argument("dst")
    parser.add_argument("owner")
    parser.add_argument("group")
    parser.add_argument("mode")

    args = parser.parse_args()

    # Emit deprecation warning once unless quiet
    if not args.quiet and not os.environ.get("INSTALL_IF_CHANGED_DEPRECATED_WARNED"):
        print("⚠️  install_if_changed.py is deprecated.", file=sys.stderr)
        print("⚠️  Use install_file_if_changed.sh instead.", file=sys.stderr)
        os.environ["INSTALL_IF_CHANGED_DEPRECATED_WARNED"] = "1"

    # Removed features must fail loudly
    if args.dry_run:
        print("❌ --dry-run is no longer supported.", file=sys.stderr)
        print("❌ Use install_file_if_changed.sh directly.", file=sys.stderr)
        sys.exit(1)

    if args.ssh_port:
        print("❌ --ssh-port is no longer supported.", file=sys.stderr)
        print("❌ Use install_file_if_changed.sh directly.", file=sys.stderr)
        sys.exit(1)

    # Resolve the shell script relative to this file
    script_dir = os.path.dirname(os.path.abspath(__file__))
    target = os.path.join(script_dir, "install_file_if_changed.sh")

    # Build argv correctly for execv: argv[0] must be the program name
    cmd = [target]

    if args.quiet:
        cmd.append("-q")

    cmd.extend([
        "", "", args.src,
        "", "", args.dst,
        args.owner, args.group, args.mode,
    ])

    os.execv(target, cmd)

if __name__ == "__main__":
    main()
