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

# Terra's manager RPM bundles the Legion Go firmware backend, device profile,
# system/user services, and SELinux policy. Its hard dependencies are only for
# Bazzite's native Steam/Game Mode session; resolving them would replace this
# image's Flatpak Steam design. Install the RPM payload without that unrelated
# Game Mode stack instead.
mapfile -t manager_rpms < <("$DNF" -q --enablerepo=terra repoquery --latest-limit=1 --location steamos-manager-powerstation)
[[ ${#manager_rpms[@]} == 1 ]] || {
    printf 'Expected one SteamOS Manager RPM, found %s.\n' "${#manager_rpms[@]}" >&2
    exit 1
}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
curl --fail --location --output "$work/steamos-manager.rpm" "${manager_rpms[0]}"
"$DNF" -y install policycoreutils
rpm --upgrade --nodeps "$work/steamos-manager.rpm"

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
