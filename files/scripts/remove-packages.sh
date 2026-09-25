#!/usr/bin/env bash

# Tell build process to exit if there are any errors.
set -oue pipefail

# `rpm-ostree override remove` aborts the whole build when a listed package is
# not installed, which makes the removal list fragile across base image /
# Fedora version bumps. Skip anything that isn't actually present.

# Disable before uninstalling, while the units and their aliases still exist.
for unit in sddm.service sddm-boot.service; do
    if [[ -f /usr/lib/systemd/system/"$unit" || -f /etc/systemd/system/"$unit" ]]; then
        systemctl disable "$unit"
    fi
done

PACKAGES=(
    firefox
    firefox-langpacks
    tuned
    tuned-ppd
    tuned-switcher
    alacritty
    waybar
    swaybg
    swaylock
    swayidle
    dunst
    fuzzel
    rofi-wayland
    wofi
    xfce-polkit
    sddm
    sddm-themes
    sddm-wayland-sway
    kwallet
    pam-kwallet
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
