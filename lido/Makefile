# lido — build an Armbian USB flasher for the chainnode fleet.
# Runs on the build host `c` (Linux, has the USB reader). Big artifacts go to build/
# and are gitignored. See README.md and SPEC.md. flash/verify-usb only ever touch a
# device that passes every USB check in scripts/find-usb.sh.

SHELL := /usr/bin/env bash
S     := scripts
BUILD ?= build
export BUILD

# Pinned to match `c` (Armbian 26.5.1 / vendor kernel 6.1.115). Override via env.
ARMBIAN_IMG ?= Armbian_26.5.1_Orangepi5-plus_trixie_vendor_6.1.115_minimal.img.xz
export ARMBIAN_IMG
IMG := $(BUILD)/$(ARMBIAN_IMG:.xz=)

.PHONY: help fetch capture-spi verify-usb flash inject usbinstall installer clean

help: ## show this help
	@grep -hE '^[a-z][a-z-]*:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | expand -t20

fetch: ## download+verify Armbian image and clone eth-docker into build/
	@$(S)/fetch.sh

capture-spi: ## clone c's PROVEN SPI (/dev/mtdblock0) into build/spi/ for bundling (run ON c)
	@$(S)/capture-spi.sh

verify-usb: ## DESTRUCTIVE: O_DIRECT capacity test on the first USB drive
	@dev=$$($(S)/find-usb.sh) && python3 $(S)/verify-usb.py "$$dev"

flash: ## write the fetched Armbian image to the first USB drive (USB-guarded)
	@$(S)/flash.sh "$(IMG)"

inject: ## bake the provisioning payload into the flashed USB rootfs (debugfs, no root)
	@$(S)/inject.sh

usbinstall: ## prepare the auto-provisioning USB flasher: ensure image, flash (USB-guarded), bake payload
	@test -f "$(IMG)" || { echo "base image missing -> fetching"; $(S)/fetch.sh; }
	@$(S)/flash.sh "$(IMG)"
	@$(S)/inject.sh
	@echo "usbinstall ready on the USB drive — boot a board from it to auto-provision"
	@echo "(stage1: NVMe install + proper SPI flashcp; stage2: config). No board was touched."

installer: usbinstall ## alias for usbinstall

clean: ## remove build artifacts (build/)
	@rm -rf "$(BUILD)" && echo "cleaned $(BUILD)"
