#!/usr/bin/env bash
# Fail on upstream template drift; optional path permits checking an extracted RPM.
set -Eeuo pipefail
template=${1:-/usr/share/doc/niri/default-config.kdl}
expected=993aa205ed47eada18b0ed85a8d4c7b31480c56c9d182840121943dd286ad080
actual=$(sha256sum "$template")
if [[ ${actual%% *} != "$expected" ]]; then
    printf '%s\n' 'niri template changed. Review files/system/usr/etc/niri/config.kdl against the packaged default, then update its provenance and check-niri-config-drift.sh.' >&2
    exit 1
fi
printf '%s\n' 'niri stock template matches the reviewed Fedora 44 / 26.04 template.'
