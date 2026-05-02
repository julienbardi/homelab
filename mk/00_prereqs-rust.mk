# mk/00_prereqs-rust.mk
.SHELL := /bin/bash
.ONESHELL:

.PHONY: rust-system rust-system-uninstall

# allow forcing reinstall with FORCE=1
rust-system: ensure-run-as-root
	@# Detect user vs root installs separately and always show versions
	set -euo pipefail

	[ -n "$(INSTALL_PATH)" ] || { echo "error: INSTALL_PATH not set"; exit 1; }
	[ -n "$(run_as_root)" ] || { echo "error: run_as_root not defined"; exit 1; }

	# probe_toolchain: populate USER_CARGO_PATH, USER_RUSTC_PATH, ROOT_*_VER, ACTIVE_*
	probe_toolchain() {
		USER_CARGO_PATH=$$(command -v cargo 2>/dev/null || true)
		USER_RUSTC_PATH=$$(command -v rustc 2>/dev/null || true)
		ROOT_CARGO_PATH="$(INSTALL_PATH)/cargo"
		ROOT_RUSTC_PATH="$(INSTALL_PATH)/rustc"
		ROOT_CARGO_OK=$$( [ -x "$$ROOT_CARGO_PATH" ] && echo yes || echo no )
		ROOT_RUSTC_OK=$$( [ -x "$$ROOT_RUSTC_PATH" ] && echo yes || echo no )
		USER_CARGO_VER=$$( if command -v cargo >/dev/null 2>&1; then cargo -V 2>/dev/null || echo "cargo unknown"; else echo "cargo none"; fi )
		USER_RUSTC_VER=$$( if command -v rustc >/dev/null 2>&1; then rustc --version 2>/dev/null || echo "rustc unknown"; else echo "rustc none"; fi )
		ROOT_CARGO_VER=$$( if [ -x "$$ROOT_CARGO_PATH" ]; then "$$ROOT_CARGO_PATH" -V 2>/dev/null || echo "cargo unknown"; else echo "cargo none"; fi )
		ROOT_RUSTC_VER=$$( if [ -x "$$ROOT_RUSTC_PATH" ]; then "$$ROOT_RUSTC_PATH" --version 2>/dev/null || echo "rustc unknown"; else echo "rustc none"; fi )
		ACTIVE_CARGO=$$(command -v cargo 2>/dev/null || echo none)
		ACTIVE_RUSTC=$$(command -v rustc 2>/dev/null || echo none)
		# capture root PATH once and reuse in summaries
		ROOT_PATH=$$($(run_as_root) sh -c 'printf "%s" "$$PATH"')
		# New: Resolve the actual physical location of the active binaries
		ACTIVE_CARGO_REAL=$$(if [ "$$ACTIVE_CARGO" != "none" ]; then readlink -f "$$ACTIVE_CARGO"; else echo "none"; fi)
		ROOT_CARGO_REAL=$$(if [ -x "$$ROOT_CARGO_PATH" ]; then readlink -f "$$ROOT_CARGO_PATH"; else echo "none"; fi)
	}


	# reusable summary printer (call after any install/re-probe)
	print_summary() {
		printf 'ℹ️ cargo present (user: %s; root: %s)\n' "$$USER_CARGO_PATH" "$$ROOT_CARGO_OK"
		# Explicitly show the link resolution for the root version
		if [ "$$ROOT_CARGO_OK" = "yes" ]; then
			printf '   root link: %s -> %s\n' "$$ROOT_CARGO_PATH" "$$ROOT_CARGO_REAL"
		fi
		printf '   active:    %s -> %s\n' "$$ACTIVE_CARGO" "$$ACTIVE_CARGO_REAL"

		printf '   user versions: %s; %s\n' "$$USER_RUSTC_VER" "$$USER_CARGO_VER"
		printf '   root versions: %s; %s\n' "$$ROOT_RUSTC_VER" "$$ROOT_CARGO_VER"
		printf '   root PATH: %s\n' "$$ROOT_PATH"

		# The authoritative conflict check
		if [ "$$ACTIVE_CARGO_REAL" != "$$ROOT_CARGO_REAL" ]; then
			printf '⚠️  WARNING: Your shell is using a toolchain DIFFERENT from the system root install.\n'
			printf '   To use the system version, ensure %s is earlier in your PATH than ~/.cargo/bin\n' "$(INSTALL_PATH)"
		fi
	}

	probe_toolchain

	# Decide whether we need to install:
	# - install if FORCE is set
	# - otherwise install only if neither user nor root cargo exists
	if [ -n "$(FORCE)" ] || { [ -z "$$USER_CARGO_PATH" ] && [ "$$ROOT_CARGO_OK" != "yes" ]; }; then
		need_install=yes
	else
		need_install=no
	fi

	# sanity-check run_as_root actually runs a command
	$(run_as_root) sh -c 'true' >/dev/null 2>&1 || { echo "error: run_as_root failed to run"; exit 1; }

	if [ "$$need_install" = "yes" ]; then
		# Force the environment to be root-centric for the installer
		$(run_as_root) env CARGO_HOME=/root/.cargo RUSTUP_HOME=/root/.rustup sh -e -c '\
			if [ -n "$$VERBOSE" ] && [ "$$VERBOSE" != "0" ]; then set -x; fi; \
			install -d -o root -g root -m 0755 "$(INSTALL_PATH)"; \
			\
			echo "📦 Installing Rust via rustup (root context)..."; \
			command -v curl >/dev/null || { echo "error: curl not installed"; exit 1; }
			curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path >/dev/null 2>&1; \
			\
			ln -sf /root/.cargo/bin/cargo "$(INSTALL_PATH)/cargo"; \
			ln -sf /root/.cargo/bin/rustc "$(INSTALL_PATH)/rustc"; \
			\
			# Optional: Ensure /usr/local/bin symlinks for zero-config PATH
			if [ -d /usr/local/bin ] && [ ! -e /usr/local/bin/cargo ]; then \
				ln -sf "$(INSTALL_PATH)/cargo" /usr/local/bin/cargo; \
				ln -sf "$(INSTALL_PATH)/rustc" /usr/local/bin/rustc; \
			fi \
		'
	fi

	# re-probe after possible install and re-capture root PATH, then print a single summary
	probe_toolchain
	print_summary

	# if INSTALL_PATH is not on PATH and /usr/local/bin not writable, print instruction
	if ! echo "$$PATH" | tr ':' '\n' | grep -qx "$(INSTALL_PATH)"; then
		if [ ! -w /usr/local/bin ]; then
			printf 'NOTE: %s is not on your PATH. Add it to your shell profile, e.g.:\n' "$(INSTALL_PATH)"
			printf '  export PATH="%s:$$PATH"\n' "$(INSTALL_PATH)"
		fi
	fi

# reversible uninstall that moves things aside instead of deleting
rust-system-uninstall: ensure-run-as-root
	@$(run_as_root) sh -eux -c '\
		ts=$$(date +%s); \
		[ -e "$(INSTALL_PATH)/cargo" ] && mv -f "$(INSTALL_PATH)/cargo" "$(INSTALL_PATH)/cargo.uninstalled.$$ts" || true; \
		[ -e "$(INSTALL_PATH)/rustc" ] && mv -f "$(INSTALL_PATH)/rustc" "$(INSTALL_PATH)/rustc.uninstalled.$$ts" || true; \
		[ -d /root/.cargo ] && mv -f /root/.cargo /root/.cargo.uninstalled.$$ts || true; \
		[ -d /root/.rustup ] && mv -f /root/.rustup /root/.rustup.uninstalled.$$ts || true; \
		[ -L /usr/local/bin/cargo ] && rm -f /usr/local/bin/cargo || true; \
		[ -L /usr/local/bin/rustc ] && rm -f /usr/local/bin/rustc || true; \
		echo "✅ rust-system uninstalled (moved to backups)"; \
	'
