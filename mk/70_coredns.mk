# mk/70_coredns.mk
# Idempotent Makefile fragment to build CoreDNS with headscale + doh,
# install binary and Corefile, create runtime user, systemd unit and enable service.
# Depends on 'headscale' target which ensures the headscale source is present.

.ONESHELL:
SHELL := /bin/bash

# Paths and configuration
COREDNS_SRC ?= /home/julie/src/coredns-src
COREDNS_OUT ?= /home/julie/src/coredns
COREDNS_BIN := $(COREDNS_OUT)/coredns
COREFILE_SRC ?= $(COREDNS_SRC)/Corefile
COREFILE_DEST ?= /etc/coredns/Corefile

GIT_REPO ?= https://github.com/coredns/coredns.git
CORE_DNS_REF ?= origin/HEAD

# Plugins (import paths)
HEADSCALE_IMPORT ?= github.com/juanfont/headscale/coredns/headscale
DOH_IMPORT ?= github.com/coredns/doh

# Optional: where to clone headscale source (dependency target)
HEADSCALE_REPO ?= https://github.com/juanfont/headscale.git
HEADSCALE_SRC ?= /home/julie/src/headscale

# Runtime/service
RUN_USER ?= coredns
SERVICE_NAME ?= coredns
SYSTEMD_UNIT := /etc/systemd/system/$(SERVICE_NAME).service
OVERWRITE_UNIT ?= 0

.PHONY: install-pkg-coredns headscale

# Ensure headscale source exists (dependency)
headscale_OLD:
	set -euo pipefail
	if [ ! -d "$(HEADSCALE_SRC)" ]; then \
	echo "Cloning headscale to $(HEADSCALE_SRC)"; \
	git clone --depth 1 "$(HEADSCALE_REPO)" "$(HEADSCALE_SRC)"; \
	else \
	echo "Updating headscale at $(HEADSCALE_SRC)"; \
	git -C "$(HEADSCALE_SRC)" fetch --depth 1 origin && git -C "$(HEADSCALE_SRC)" reset --hard origin/HEAD || true; \
	fi
	@echo "headscale: ready"

# Build, install and deploy CoreDNS (depends on headscale)
install-pkg-coredns: headscale
	@echo "Building and installing CoreDNS..."
	set -euo pipefail

	# check prerequisites
	if ! command -v go >/dev/null 2>&1; then \
	echo "ERROR: 'go' not found in PATH; install Go and retry"; exit 1; \
	fi

	# clone or update CoreDNS source (idempotent)
	if [ ! -d "$(COREDNS_SRC)" ]; then \
	echo "Cloning CoreDNS to $(COREDNS_SRC)"; \
	git clone --depth 1 "$(GIT_REPO)" "$(COREDNS_SRC)"; \
	else \
	echo "Updating CoreDNS at $(COREDNS_SRC)"; \
	git -C "$(COREDNS_SRC)" fetch --depth 1 origin && git -C "$(COREDNS_SRC)" reset --hard "$(CORE_DNS_REF)"; \
	fi

	# ensure plugin.cfg contains headscale and doh entries (idempotent)
	mkdir -p "$(COREDNS_SRC)"
	touch "$(COREDNS_SRC)/plugin.cfg"
	grep -Fqx "headscale:$(HEADSCALE_IMPORT)" "$(COREDNS_SRC)/plugin.cfg" || echo "headscale:$(HEADSCALE_IMPORT)" >> "$(COREDNS_SRC)/plugin.cfg"
	grep -Fqx "doh:$(DOH_IMPORT)" "$(COREDNS_SRC)/plugin.cfg" || echo "doh:$(DOH_IMPORT)" >> "$(COREDNS_SRC)/plugin.cfg"

	# fetch module deps and build
	cd "$(COREDNS_SRC)" && go mod tidy
	cd "$(COREDNS_SRC)" && make

	# prepare runtime user and directories
	if ! id -u $(RUN_USER) >/dev/null 2>&1; then \
	sudo useradd --system --no-create-home --shell /usr/sbin/nologin $(RUN_USER) || true; \
	fi
	sudo install -d -m 0755 -o $(RUN_USER) -g $(RUN_USER) /etc/coredns /var/lib/coredns || true

	# install Corefile: prefer source Corefile if present, otherwise write a safe default
	if [ -f "$(COREFILE_SRC)" ]; then \
	echo "Installing Corefile from $(COREFILE_SRC) -> $(COREFILE_DEST)"; \
	sudo install -m 0644 "$(COREFILE_SRC)" "$(COREFILE_DEST)"; \
	else \
	echo "No Corefile in source; writing default Corefile to $(COREFILE_DEST)"; \
	sudo tee "$(COREFILE_DEST)" > /dev/null <<'EOF'
	tailnet:8053 {
	headscale {
	base_domain tailnet
	listen 127.0.0.1:8053
	}
	log
	errors
	}
	
	.:8053 {
	forward . 127.0.0.1:53
	cache 30
	log
	errors
	}
	EOF
	fi
	# ensure ownership and permissions for Corefile
	sudo install -m 0644 -o $(RUN_USER) -g $(RUN_USER) "$(COREFILE_DEST)" "$(COREFILE_DEST)"
	
	# atomic install of binary with backup
	mkdir -p "$(COREDNS_OUT)"
	if [ -f "$(COREDNS_BIN)" ]; then sudo cp "$(COREDNS_BIN)" "$(COREDNS_BIN).bak" || true; fi
	sudo install -m 0755 -o root -g root "$(COREDNS_SRC)/coredns" "$(COREDNS_BIN)"
	
	# create or optionally overwrite systemd unit
	if [ ! -f "$(SYSTEMD_UNIT)" ] || [ "$(OVERWRITE_UNIT)" = "1" ]; then \
	echo "Writing systemd unit to $(SYSTEMD_UNIT)"; \
	sudo tee "$(SYSTEMD_UNIT)" > /dev/null <<EOF
	[Unit]
	Description=CoreDNS
	After=network.target
	
	[Service]
	ExecStart=$(COREDNS_BIN) -conf /etc/coredns/Corefile
	WorkingDirectory=/etc/coredns
	User=$(RUN_USER)
	Group=$(RUN_USER)
	Restart=on-failure
	LimitNOFILE=65536
	
	[Install]
	WantedBy=multi-user.target
	EOF
	else \
	echo "systemd unit exists at $(SYSTEMD_UNIT); set OVERWRITE_UNIT=1 to replace"; \
	fi
	
	# enable and start service (idempotent)
	sudo systemctl daemon-reload
	sudo systemctl enable $(SERVICE_NAME) || true
	if sudo systemctl is-active --quiet $(SERVICE_NAME); then \
	sudo systemctl restart $(SERVICE_NAME) || true; \
	else \
	sudo systemctl start $(SERVICE_NAME) || true; \
	fi
	
	# verification hints (non-fatal)
	"$(COREDNS_BIN)" -plugins | grep -E 'headscale|doh' >/dev/null 2>&1 || echo "WARNING: built binary does not list headscale/doh in -plugins output"
	"$(COREDNS_BIN)" -conf /etc/coredns/Corefile >/dev/null 2>&1 || echo "NOTE: Corefile parse failed; check /etc/coredns/Corefile and journalctl -u $(SERVICE_NAME)"
	
	@echo "install-pkg-coredns: done (binary -> $(COREDNS_BIN))"
