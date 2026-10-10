#!/usr/bin/env bash

# InputPlumber's Legion Go profile is packaged by Terra, as on Bazzite. Keep
# the repository disabled after installation so it cannot affect later image
# upgrades or unrelated dependency resolution.
set -Eeuo pipefail

DNF=dnf5
command -v "$DNF" >/dev/null 2>&1 || DNF=dnf

"$DNF" -y install --nogpgcheck \
    --repofrompath=terra-bootstrap,'https://repos.fyralabs.com/terra$releasever' \
    terra-release \
    terra-release-extras
"$DNF" -y --enablerepo=terra install inputplumber
"$DNF" config-manager setopt terra.enabled=0 terra-extras.enabled=0

profile=/usr/share/inputplumber/devices/50-legion_go.yaml
if [[ ! -r $profile ]] || ! grep -q 'name: Lenovo Legion Go' "$profile"; then
    printf 'InputPlumber Legion Go profile is missing: %s\n' "$profile" >&2
    exit 1
fi
