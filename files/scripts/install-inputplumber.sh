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
# Native Steam needs 32-bit PipeWire, whose AAC dependency conflicts with the
# single-architecture libfdk-aac inherited from the base image. Let DNF replace
# it while resolving the complete native Steam transaction.
"$DNF" -y --enablerepo=terra --enablerepo=terra-extras install --allowerasing \
    inputplumber \
    steam \
    gamescope-session \
    gamescope-session-steam \
    gamescope-session-ogui-steam \
    opengamepadui \
    steamos-manager-powerstation

# The provider package pulls in the manager daemon. Both daemons are required:
# root owns firmware attributes and the user daemon exports the session API.
test -f /usr/lib/systemd/system/steamos-manager.service
test -f /usr/lib/systemd/user/steamos-manager.service
"$DNF" config-manager setopt terra.enabled=0 terra-extras.enabled=0

profile=/usr/share/inputplumber/devices/50-legion_go.yaml
if [[ ! -r $profile ]] || ! grep -q 'name: Lenovo Legion Go' "$profile"; then
    printf 'InputPlumber Legion Go profile is missing: %s\n' "$profile" >&2
    exit 1
fi
