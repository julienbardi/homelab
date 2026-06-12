# Detect WSL2 environment
WSL2_ENV := $(shell grep -qi microsoft /proc/version && echo 1 || echo 0)
