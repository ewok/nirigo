#!/usr/bin/env bash

# Tell build process to exit if there are any errors.
set -oue pipefail

# Bazzite now ships its gamescope as terra-gamescope. The previous COPR path
# can leave Fedora's preinstalled gamescope in place when both packages have
# the same version, defeating --from-repo and failing the provenance check.
# install-inputplumber.sh bootstraps Terra and Terra Extras first, then disables
# both; enable them only for this transaction.

DNF=dnf5
command -v "$DNF" >/dev/null 2>&1 || DNF=dnf

"$DNF" -y install --allowerasing --enablerepo=terra --enablerepo=terra-extras \
    terra-gamescope.x86_64 \
    terra-gamescope-libs.x86_64 \
    terra-gamescope-libs.i686
"$DNF" config-manager setopt terra.enabled=0 terra-extras.enabled=0

provider="$(rpm -q --whatprovides /usr/bin/gamescope)"
rpm -qi "$provider"
if [[ $provider != terra-gamescope-* ]]; then
    echo "Expected terra-gamescope to provide /usr/bin/gamescope, got '$provider'" >&2
    exit 1
fi
