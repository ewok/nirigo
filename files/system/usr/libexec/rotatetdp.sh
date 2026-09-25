#!/usr/bin/bash
# Prints the current mode; `rotate` changes it only after a successful HHD call.
set -Eeuo pipefail
if [[ $# -gt 1 || ( $# -eq 1 && $1 != rotate ) ]]; then
    printf 'Usage: %s [rotate]\n' "$0" >&2
    exit 2
fi
value=$(hhdctl get tdp.lenovo.tdp.mode)
current_mode=${value#*=}
case "$current_mode" in
    quiet) next_mode=balanced ;;
    balanced) next_mode=performance ;;
    performance) next_mode=custom ;;
    custom) next_mode=quiet ;;
    *) printf 'Unknown TDP mode: %s\n' "$current_mode" >&2; exit 1 ;;
esac
if [[ ${1:-} == rotate ]]; then
    hhdctl set tdp.lenovo.tdp.mode="$next_mode" >/dev/null
    current_mode=$next_mode
fi
printf '%s\n' "$current_mode"
