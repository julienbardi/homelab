# ============================================================
# mk/80_openssh9_pi.mk — OpenSSH 9 + PQ KEX on Raspberry Pi
# ============================================================
# Usage (on the Pi, as root):
#   sudo make -f mk/80_openssh9_pi.mk openssh9-enable
#
# No recursive make. No NAS involvement. Pi only.

OPENSSH9_VERSION      := 9.7p1
OPENSSH9_TARBALL      := openssh-$(OPENSSH9_VERSION).tar.gz
OPENSSH9_URL          := https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/$(OPENSSH9_TARBALL)

# TODO: set to the real SHA256 of openssh-9.7p1.tar.gz
OPENSSH9_SHA256       := CHANGE_ME_SHA256_FOR_$(OPENSSH9_TARBALL)

OPENSSH9_SRC_DIR      := /usr/local/src
OPENSSH9_TARBALL_PATH := $(OPENSSH9_SRC_DIR)/$(OPENSSH9_TARBALL)
OPENSSH9_BUILD_DIR    := $(OPENSSH9_SRC_DIR)/openssh-$(OPENSSH9_VERSION)

OPENSSH9_PREF_FILE    := /etc/apt/preferences.d/openssh-local-build.pref

.PHONY: \
	openssh9-enable \
	openssh9-download \
	openssh9-verify \
	openssh9-build \
	openssh9-install \
	openssh9-pin \
	openssh9-verify-pq

openssh9-enable: openssh9-download openssh9-verify openssh9-build openssh9-install openssh9-pin openssh9-verify-pq
	@echo "✅ OpenSSH $(OPENSSH9_VERSION) built, installed, pinned, and PQ-KEX verified on Raspberry Pi"

openssh9-download:
	@set -eu; \
	mkdir -p "$(OPENSSH9_SRC_DIR)"; \
	if [ -f "$(OPENSSH9_TARBALL_PATH)" ]; then \
		echo "ℹ️ $(OPENSSH9_TARBALL) already present at $(OPENSSH9_TARBALL_PATH)"; \
	else \
		echo "⬇️  Downloading $(OPENSSH9_TARBALL) from $(OPENSSH9_URL)"; \
		curl -fsSL "$(OPENSSH9_URL)" -o "$(OPENSSH9_TARBALL_PATH)"; \
	fi

openssh9-verify: openssh9-download
	@set -eu; \
	if [ "$(OPENSSH9_SHA256)" = "CHANGE_ME_SHA256_FOR_$(OPENSSH9_TARBALL)" ]; then \
		echo "❌ OPENSSH9_SHA256 is not set. Edit mk/80_openssh9_pi.mk and set the real SHA256."; \
		exit 1; \
	fi; \
	echo "$(OPENSSH9_SHA256)  $(OPENSSH9_TARBALL_PATH)" | sha256sum -c - >/dev/null 2>&1 || { \
		echo "❌ SHA256 mismatch for $(OPENSSH9_TARBALL_PATH)"; \
		exit 1; \
	}; \
	echo "✅ SHA256 verified for $(OPENSSH9_TARBALL_PATH)"

openssh9-build: openssh9-verify
	@set -eu; \
	if [ ! -d "$(OPENSSH9_BUILD_DIR)" ]; then \
		echo "📦 Extracting $(OPENSSH9_TARBALL) into $(OPENSSH9_SRC_DIR)"; \
		tar -C "$(OPENSSH9_SRC_DIR)" -xf "$(OPENSSH9_TARBALL_PATH)"; \
	fi; \
	cd "$(OPENSSH9_BUILD_DIR)"; \
	echo "🔧 Configuring OpenSSH $(OPENSSH9_VERSION)"; \
	./configure \
	  --prefix=/usr \
	  --sysconfdir=/etc/ssh \
	  --with-pam \
	  --with-ssl-engine \
	  --with-privsep-path=/var/lib/sshd \
	  --with-md5-passwords; \
	echo "🛠  Building OpenSSH $(OPENSSH9_VERSION)"; \
	make -j"$$(nproc)"

openssh9-install: openssh9-build
	@set -eu; \
	cd "$(OPENSSH9_BUILD_DIR)"; \
	echo "📥 Installing OpenSSH $(OPENSSH9_VERSION)"; \
	make install; \
	if command -v ssh >/dev/null 2>&1; then \
		echo "🔍 Installed ssh version: $$(ssh -V 2>&1)"; \
	else \
		echo "⚠️ ssh not found in PATH after install"; \
	fi; \
	echo "🔄 Restarting SSH service (if present)"; \
	if systemctl list-unit-files | grep -q "^ssh\.service"; then \
		systemctl restart ssh; \
	elif systemctl list-unit-files | grep -q "^sshd\.service"; then \
		systemctl restart sshd; \
	else \
		echo "⚠️ No ssh/sshd systemd unit found; skipping restart"; \
	fi

openssh9-pin:
	@set -eu; \
	mkdir -p /etc/apt/preferences.d; \
	printf "%s\n" \
"Package: openssh-client openssh-server" \
"Pin: release *" \
"Pin-Priority: -1" \
		> "$(OPENSSH9_PREF_FILE)"; \
	echo "📌 Pinned distro openssh packages via $(OPENSSH9_PREF_FILE)"

openssh9-verify-pq:
	@set -eu; \
	if ! command -v ssh >/dev/null 2>&1; then \
		echo "❌ ssh not found in PATH"; \
		exit 1; \
	fi; \
	if ssh -Q kex 2>/dev/null | grep -q "sntrup761x25519-sha512@openssh.com"; then \
		echo "✅ PQ KEX available: sntrup761x25519-sha512@openssh.com"; \
	else \
		echo "❌ PQ KEX not found in ssh -Q kex output"; \
		ssh -Q kex 2>/dev/null || true; \
		exit 1; \
	fi
