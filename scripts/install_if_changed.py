#!/usr/bin/env python3
"""
install_if_changed.py — atomic, idempotent install script for local and remote targets

Usage:

  # Local copy/install:
  ./install_if_changed.py sourcefile.txt /path/to/dest.txt root root 0644

  # Remote copy/install:
  ./install_if_changed.py sourcefile.txt user@remotehost:/path/to/dest.txt root root 0644

  # Quiet mode (suppress output):
  ./install_if_changed.py -q sourcefile.txt /path/to/dest.txt root root 0644

  # Dry run (show what would change, no file is modified):
  ./install_if_changed.py -n sourcefile.txt /path/to/dest.txt root root 0644

  # Remote copy/install with custom SSH port:
  ./install_if_changed.py --ssh-port 2222 sourcefile.txt user@remotehost:/path/to/dest.txt root root 0644

Exit codes:
 0 = destination up-to-date (no changes)
 3 = destination updated or would be updated (dry run)
 1 = error (invalid arguments, failure, missing source file, etc.)

Examples:

a) Calling from a Makefile

.PHONY: install-file
install-file:
	@./scripts/install_if_changed.py "$(SRC)" "$(DST)" "$(OWNER)" "$(GROUP)" "$(MODE)"

Make variables:

 SRC=/path/to/sourcefile.txt
 DST=/desired/target/path.txt
 OWNER=root
 GROUP=root
 MODE=0644

b) Calling from a bash script

#!/bin/bash
SRC="/path/to/sourcefile.txt"
DST="/desired/target/path.txt"
OWNER="root"
GROUP="root"
MODE="0644"

./scripts/install_if_changed.py "$SRC" "$DST" "$OWNER" "$GROUP" "$MODE"

"""
import argparse
import os
import sys
import stat
import tempfile
import shutil
import subprocess
import filecmp
import pwd
import grp

EXIT_UNCHANGED = 0
EXIT_CHANGED = 3
EXIT_FAILURE = 1

def run_cmd(cmd, capture_output=True):
    """Run a shell command returning (returncode, stdout, stderr)."""
    process = subprocess.run(cmd, shell=False,
                             stdout=subprocess.PIPE if capture_output else None,
                             stderr=subprocess.PIPE if capture_output else None,
                             universal_newlines=True)
    return process.returncode, process.stdout if capture_output else None, process.stderr if capture_output else None

def parse_remote_path(path):
    """If path like user@host:/path, parse into (user, host, path), else (None, None, path)."""
    if ':' in path and '@' in path.split(':')[0]:
        userhost, remote_path = path.split(':', 1)
        if '@' in userhost:
            user, host = userhost.split('@', 1)
        else:
            user, host = None, userhost
        return user, host, remote_path
    else:
        return None, None, path

def stat_local(path):
    st = os.stat(path)
    return st.st_mode & 0o7777, st.st_uid, st.st_gid

def same_metadata_local(src, dst):
    try:
        m1, uid1, gid1 = stat_local(src)
        m2, uid2, gid2 = stat_local(dst)
        return m1 == m2 and uid1 == uid2 and gid1 == gid2
    except FileNotFoundError:
        return False

def uidgid_from_name(owner, group):
    try:
        uid = pwd.getpwnam(owner).pw_uid
    except KeyError:
        print(f"❌ Unknown user: {owner}", file=sys.stderr)
        sys.exit(EXIT_FAILURE)
    try:
        gid = grp.getgrnam(group).gr_gid
    except KeyError:
        print(f"❌ Unknown group: {group}", file=sys.stderr)
        sys.exit(EXIT_FAILURE)
    return uid, gid

def filecmp_local(src, dst):
    return filecmp.cmp(src, dst, shallow=False)

def read_remote_file(user, host, path, local_tmp, port):
    target = f"{user+'@' if user else ''}{host}:{path}"
    cmd = ["scp", "-P", str(port), target, local_tmp]
    rc = subprocess.call(cmd)
    return rc == 0

def same_file_remote(src, user, host, dst, port):
    # Download remote file to temp and do local compare
    with tempfile.NamedTemporaryFile() as tmpfile:
        rc = read_remote_file(user, host, dst, tmpfile.name, port)
        if not rc:
            return False
        return filecmp_local(src, tmpfile.name)

def same_metadata_remote(user, host, src, dst, port):
    # Check mode, uid, gid on remote file via ssh stat
    target = f"{user+'@' if user else ''}{host}"
    proc = subprocess.run(["ssh", "-p", str(port), target, "stat", "-c", "%a %u %g", dst],
                          stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE,
                          universal_newlines=True)
    if proc.returncode != 0:
        return False

    try:
        mode_str, uid_str, gid_str = proc.stdout.strip().split()
        mode_remote = int(mode_str, 8)
        uid_remote = int(uid_str)
        gid_remote = int(gid_str)
    except Exception:
        return False

    stat_src = os.stat(src)
    mode_src = stat_src.st_mode & 0o7777
    uid_src = stat_src.st_uid
    gid_src = stat_src.st_gid

    return mode_src == mode_remote and uid_src == uid_remote and gid_src == gid_remote

def ssh_scp_copy(src, user, host, port, tmpname):
    target = f"{user+'@' if user else ''}{host}:{tmpname}"
    scp_cmd = ["scp", "-P", str(port), src, target]
    rc = subprocess.call(scp_cmd)
    if rc != 0:
        print(f"❌ Failed to copy file to remote temp {tmpname}", file=sys.stderr)
        sys.exit(EXIT_FAILURE)

def ssh_remote_chown_chmod_move(user, host, port, tmpname, dst, owner, group, mode):
    target = f"{user+'@' if user else ''}{host}"
    cmd = f"chown {owner}:{group} '{tmpname}' && chmod {mode} '{tmpname}' && mv '{tmpname}' '{dst}'"
    rc = subprocess.call(["ssh", "-p", str(port), target, cmd])
    if rc != 0:
        print("❌ Failed to set ownership/permissions or move file on remote", file=sys.stderr)
        sys.exit(EXIT_FAILURE)

def install_local(src, dst, owner, group, mode, dry_run, quiet):
    uid, gid = uidgid_from_name(owner, group)

    if os.path.isfile(dst) and filecmp_local(src, dst) and same_metadata_local(src, dst):
        if not quiet:
            print(f"⚪ {dst} unchanged")
        sys.exit(EXIT_UNCHANGED)

    if dry_run:
        if not quiet:
            print(f"🔍 {dst} would be updated (dry-run)")
        sys.exit(EXIT_CHANGED)

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(dst))
    os.close(tmp_fd)

    try:
        shutil.copy2(src, tmp_path)
        os.chown(tmp_path, uid, gid)
        os.chmod(tmp_path, int(mode, 8))
        os.rename(tmp_path, dst)
        if not quiet:
            print(f"🔄 {dst} updated")
    except Exception as e:
        print(f"❌ Failed to install file: {e}", file=sys.stderr)
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        sys.exit(EXIT_FAILURE)

    sys.exit(EXIT_CHANGED)

def install_remote(src, dst_full, owner, group, mode, dry_run, quiet, ssh_port):
    user, host, dst = parse_remote_path(dst_full)
    if user is None or host is None:
        print("❌ Invalid remote destination syntax", file=sys.stderr)
        sys.exit(EXIT_FAILURE)

    if same_file_remote(src, user, host, dst, ssh_port) and same_metadata_remote(user, host, src, dst, ssh_port):
        if not quiet:
            print(f"⚪ {dst_full} unchanged")
        sys.exit(EXIT_UNCHANGED)

    if dry_run:
        if not quiet:
            print(f"🔍 {dst_full} would be updated (dry-run)")
        sys.exit(EXIT_CHANGED)

    base_dir = os.path.dirname(dst)
    tmpname = base_dir + "/.install_if_changed_tmp_" + next(tempfile._get_candidate_names())

    ssh_scp_copy(src, user, host, ssh_port, tmpname)

    ssh_remote_chown_chmod_move(user, host, ssh_port, tmpname, dst, owner, group, mode)

    if not quiet:
        print(f"🔄 {dst_full} updated")

    sys.exit(EXIT_CHANGED)

def main():
    parser = argparse.ArgumentParser(description="install_if_changed: atomic, idempotent install script supporting local and remote")
    parser.add_argument('-q', '--quiet', action='store_true', help='suppress output')
    parser.add_argument('-n', '--dry-run', action='store_true', help='do not modify destination; only report what would change')
    parser.add_argument('--ssh-port', type=int, default=22, help='SSH port to use for remote connections (default 22)')
    parser.add_argument('src', help='source file path')
    parser.add_argument('dst', help='destination file path (local or user@host:/path)')
    parser.add_argument('owner', help='user owner name')
    parser.add_argument('group', help='group owner name')
    parser.add_argument('mode', help='octal file mode (e.g. 0644)')

    args = parser.parse_args()

    if not os.path.isfile(args.src):
        print(f"❌ Source file not found: {args.src}", file=sys.stderr)
        sys.exit(EXIT_FAILURE)

    user, host, _ = parse_remote_path(args.dst)

    if user and host:
        install_remote(args.src, args.dst, args.owner, args.group, args.mode, args.dry_run, args.quiet, ssh_port=args.ssh_port)
    else:
        install_local(args.src, args.dst, args.owner, args.group, args.mode, args.dry_run, args.quiet)

if __name__ == '__main__':
    main()
