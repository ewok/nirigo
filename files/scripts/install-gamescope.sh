#!/usr/bin/env bash

# Tell build process to exit if there are any errors.
set -oue pipefail

# Install Bazzite's patched gamescope (handheld fixes: panel orientation,
# HDR, Steam Deck/Legion Go quirks) from the bazzite-org/bazzite-multilib COPR.
#
# That COPR also ships replacements for pipewire, bluez, mutter, gnome-shell,
# mangohud, Xwayland, ... We only want gamescope, so the repo is:
#   * written with a private id, disabled and limited by `includepkgs`,
#   * enabled for this single transaction only,
#   * deleted afterwards, so later builds and `rpm-ostree upgrade` never see it.
# Xwayland is allowed because gamescope may pin Bazzite's build of it.
#
# If the Bazzite build ever needs libraries newer than this Fedora release,
# this script fails loudly; fall back to Fedora's own `gamescope` package.

REPO_ID=nirigo-bazzite-multilib
REPO_FILE=/etc/yum.repos.d/${REPO_ID}.repo
COPR_URL=https://download.copr.fedorainfracloud.org/results/bazzite-org/bazzite-multilib

trap 'rm -f "$REPO_FILE"' EXIT

cat >"$REPO_FILE" <<EOF
[${REPO_ID}]
name=Bazzite multilib COPR (gamescope only)
baseurl=${COPR_URL}/fedora-\$releasever-\$basearch/
type=rpm-md
gpgcheck=1
gpgkey=${COPR_URL}/pubkey.gpg
repo_gpgcheck=0
enabled=0
includepkgs=gamescope*,xorg-x11-server-Xwayland*

# Bazzite's gamescope requires gamescope-libs(x86-32); COPR publishes the
# 32-bit builds in a separate i386 chroot.
[${REPO_ID}-i386]
name=Bazzite multilib COPR i386 (gamescope only)
baseurl=${COPR_URL}/fedora-\$releasever-i386/
type=rpm-md
gpgcheck=1
gpgkey=${COPR_URL}/pubkey.gpg
repo_gpgcheck=0
enabled=0
includepkgs=gamescope*
EOF

DNF=dnf5
command -v "$DNF" >/dev/null 2>&1 || DNF=dnf

# --from-repo forces gamescope itself to come from the COPR even if Fedora's
# version string sorts higher; dependencies may still come from Fedora.
"$DNF" -y install \
    --setopt=install_weak_deps=False \
    --enablerepo="$REPO_ID" \
    --enablerepo="${REPO_ID}-i386" \
    --from-repo="${REPO_ID},${REPO_ID}-i386" \
    gamescope

release="$(rpm -q --qf '%{RELEASE}' gamescope)"
rpm -qi gamescope
if [[ $release != *bazzite* ]]; then
    echo "Expected Bazzite's gamescope, got release '$release'" >&2
    exit 1
fi
