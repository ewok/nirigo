niri-init-config:
  #!/usr/bin/env bash
  set -euo pipefail
  aggregate=/etc/niri/nirigo.kdl
  config="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
  if [ ! -e "$aggregate" ]; then
    echo "error: $aggregate is missing, is this a nirigo image?" >&2
    exit 1
  fi
  if [ -e "$config" ]; then
    if grep -qF "$aggregate" "$config"; then
      echo "$config already includes $aggregate, nothing to do."
      exit 0
    fi
    echo "Appending the nirigo include to $config"
    printf '\n// nirigo drop-ins (Legion Go input, window rules, session services).\ninclude "%s"\n' "$aggregate" >>"$config"
  else
    echo "Seeding $config from /etc/niri/config.kdl"
    mkdir -p "$(dirname "$config")"
    cp /etc/niri/config.kdl "$config"
  fi
  echo "Done. Run 'niri validate' to check the result."

# Explicit migration: back up a personal config before adopting image defaults.
# Do not run upstream `dms setup`: this image already owns its niri config.
dms-setup:
  #!/usr/bin/env bash
  set -euo pipefail
  config="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
  niri validate --config /etc/niri/config.kdl
  mkdir -p "$(dirname "$config")"
  if [[ -e "$config" || -L "$config" ]]; then
    backup=$(mktemp "${config}.pre-dms.XXXXXX")
    cp -L -- "$config" "$backup"
    echo "Saved personal config to $backup"
    rm -- "$config"
  fi
  cp /etc/niri/config.kdl "$config"
  systemctl --user daemon-reload
  systemctl --user disable --now nirigo-swayidle.service 2>/dev/null || true
  echo 'DMS configuration installed. Log out and back in to finish switching shells.'

dms-greeter-sync:
  dms-greeter sync

# Link the image-owned plugin so updates follow the installed image.
dms-tdp-setup:
  #!/usr/bin/env bash
  set -Eeuo pipefail
  source=/usr/share/nirigo/dms-plugins/LegionGoTdp
  plugins="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins"
  target="$plugins/LegionGoTdp"
  if [[ ! -f "$source/plugin.json" ]]; then
    printf 'error: %s is missing; update to an image with the TDP plugin.\n' "$source" >&2
    exit 1
  fi
  mkdir -p -- "$plugins"
  if [[ -L "$target" && $(readlink -- "$target") == "$source" ]]; then
    printf 'Legion Go TDP is already linked.\n'
  elif [[ -e "$target" || -L "$target" ]]; then
    printf 'error: %s already exists; move it aside before installing.\n' "$target" >&2
    exit 1
  else
    ln -sT -- "$source" "$target"
  fi
  printf 'In DMS Settings → Plugins, scan and enable Legion Go TDP.\n'
  printf 'Add it to your DankBar layout and Control Center widgets.\n'

# Enroll a YubiKey (FIDO2) as a LUKS unlock method for the encrypted root.
setup-luks-fido2-unlock:
  #!/usr/bin/env bash
  sudo /usr/libexec/nirigo-luks-fido2 enroll

# Wipe the FIDO2 keyslot and revert the boot configuration.
remove-luks-fido2-unlock:
  #!/usr/bin/env bash
  sudo /usr/libexec/nirigo-luks-fido2 remove

# Show the current FIDO2 enrollment and initramfs state.
luks-fido2-status:
  #!/usr/bin/env bash
  sudo /usr/libexec/nirigo-luks-fido2 status

install-nix-disable-composefs:
  #!/usr/bin/env bash
  sudo rpm-ostree kargs --append='ostree.prepare-root.composefs=0' --reboot

install-nix:
  #!/usr/bin/env bash
  echo "Defaults  secure_path = /nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:$(sudo printenv PATH)" | sudo tee /etc/sudoers.d/nix-sudo-env
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sudo bash -s -- install ostree --no-confirm --persistence=/var/lib/nix
  # nix_systemd_file_location='/nix/var/nix/profiles/default'
  # sudo rm -f /etc/systemd/system/nix-daemon.service
  # sudo rm -f /etc/systemd/system/nix-daemon.socket
  # sudo cp $nix_systemd_file_location/lib/systemd/system/nix-daemon.service /etc/systemd/system/nix-daemon.service
  # sudo cp $nix_systemd_file_location/lib/systemd/system/nix-daemon.socket /etc/systemd/system/nix-daemon.socket

remove-nix:
  sudo /nix/nix-installer uninstall

install-bazzite-arch:
  #!/usr/bin/env bash
  distrobox-create --unshare-netns --nvidia --image ghcr.io/ublue-os/bazzite-arch --name bazzite-arch -Y
  distrobox-enter -n bazzite-arch -- distrobox-export --app steam
  distrobox-enter -n bazzite-arch -- distrobox-export --app lutris
  distrobox-enter -n bazzite-arch -- distrobox-export --app protontricks
