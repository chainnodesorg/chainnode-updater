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

.PHONY: help fetch verify-usb flash image payload clean

help: ## show this help
	@grep -hE '^[a-z][a-z-]*:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | expand -t20

fetch: ## download+verify Armbian image and clone eth-docker into build/
	@$(S)/fetch.sh

verify-usb: ## DESTRUCTIVE: O_DIRECT capacity test on the first USB drive
	@dev=$$($(S)/find-usb.sh) && python3 $(S)/verify-usb.py "$$dev"

flash: ## write the fetched Armbian image to the first USB drive (USB-guarded)
	@$(S)/flash.sh "$(IMG)"

image payload: ## NOT IMPLEMENTED YET — on-device stage1/stage2 pending spare-box validation
	@echo "make $@: not implemented yet (needs a spare Orange Pi 5 Plus to validate). See SPEC.md §5." >&2; exit 1

clean: ## remove build artifacts (build/)
	@rm -rf "$(BUILD)" && echo "cleaned $(BUILD)"
