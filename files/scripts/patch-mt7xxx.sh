#!/usr/bin/env bash

# Tell build process to exit if there are any errors.
set -oue pipefail

sudo dnf5 -y install fedora-repos-archive
sudo dnf5 -y install mt7xxx-firmware-20250808-1.fc43 --allowerasing
