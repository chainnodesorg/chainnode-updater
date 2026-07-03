#!/usr/bin/env bash
# Shared helpers for lido build scripts. Source this; do not execute it.
# WHY: one place for consistent logging and fail-loud behaviour — a scaffolded or
# unexpected path must abort (die), never silently log-and-continue.
set -euo pipefail

log()  { printf '\033[1;32m[lido]\033[0m %s\n'         "$*" >&2; }
warn() { printf '\033[1;33m[lido][warn]\033[0m %s\n'   "$*" >&2; }
die()  { printf '\033[1;31m[lido][FATAL]\033[0m %s\n'  "$*" >&2; exit 1; }

# need <tool>: abort unless an executable is on PATH.
need() { command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"; }
