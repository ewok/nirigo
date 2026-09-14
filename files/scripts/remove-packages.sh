#!/usr/bin/env bash

# Tell build process to exit if there are any errors.
set -oue pipefail

# `rpm-ostree override remove` aborts the whole build when a listed package is
# not installed, which makes the removal list fragile across base image /
# Fedora version bumps. Skip anything that isn't actually present.

PACKAGES=(
    firefox
    firefox-langpacks
    tuned
    tuned-ppd
    tuned-switcher
    alacritty
)

TO_REMOVE=()
for pkg in "${PACKAGES[@]}"; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
        TO_REMOVE+=("$pkg")
    else
        echo "Skipping '$pkg': not installed"
    fi
done

if [[ ${#TO_REMOVE[@]} -eq 0 ]]; then
    echo "Nothing to remove"
    exit 0
fi

echo "Removing: ${TO_REMOVE[*]}"
rpm-ostree override remove "${TO_REMOVE[@]}"
