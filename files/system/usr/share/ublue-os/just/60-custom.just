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

# Initialize the system daemon for the desktop user and verify Legion Go TDP.
hhd-setup:
  #!/usr/bin/env bash
  set -Eeuo pipefail
  if [[ $(id -u) == 0 ]]; then
    printf 'Run ujust hhd-setup as your desktop user, without sudo. It requests sudo when needed.\n' >&2
    exit 1
  fi
  user=$(id -un)
  # Upstream passes %i (not unescaped %I) to --user; preserve username hyphens.
  unit="hhd@$user.service"
  diagnostics() {
    printf 'Inspect HHD with: systemctl status %q\n' "$unit" >&2
    printf 'Read its logs with: sudo journalctl -b -u %q --no-pager -n 80\n' "$unit" >&2
  }
  # HHD instances share the API socket and controller devices.
  active=$(systemctl list-units --all --plain --no-legend --no-pager --state=active,activating,reloading,deactivating 'hhd*.service')
  enabled=$(systemctl list-unit-files --no-legend --no-pager --state=enabled,enabled-runtime 'hhd*.service')
  while read -r other _; do
    if [[ -n "$other" && "$other" != "$unit" ]]; then
      printf 'error: %s is active or enabled; disable that HHD instance before setting up %s.\n' "$other" "$unit" >&2
      exit 1
    fi
  done <<<"$active
  $enabled"
  if ! sudo systemctl enable --now "$unit"; then
    diagnostics
    exit 1
  fi
  # Type=simple may be active before the API and device plugins are ready.
  for ((attempt=0; attempt<15; attempt++)); do
    if mode=$(sudo -n timeout 2s hhdctl get tdp.lenovo.tdp.mode --values 2>&1); then
      case "$mode" in
        quiet|balanced|performance|custom)
          printf 'HHD enabled and ready. Current TDP profile: %s\n' "$mode"
          exit 0
          ;;
      esac
    fi
    sleep 1
  done
  printf 'error: HHD did not provide a valid Legion Go TDP profile. Last response: %s\n' "$mode" >&2
  diagnostics
  exit 1

# Start HHD and link the image-owned plugin so updates follow the installed image.
dms-tdp-setup:
  #!/usr/bin/env bash
  set -Eeuo pipefail
  if [[ $(id -u) == 0 ]]; then
    printf 'Run ujust dms-tdp-setup as your desktop user, without sudo.\n' >&2
    exit 1
  fi
  source=/usr/share/nirigo/dms-plugins/LegionGoTdp
  plugins="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins"
  target="$plugins/LegionGoTdp"
  if [[ ! -f "$source/plugin.json" ]]; then
    printf 'error: %s is missing; update to an image with the TDP plugin.\n' "$source" >&2
    exit 1
  fi
  if [[ -L "$target" && $(readlink -- "$target") == "$source" ]]; then
    printf 'Legion Go TDP is already linked.\n'
  elif [[ -e "$target" || -L "$target" ]]; then
    printf 'error: %s already exists; move it aside before installing.\n' "$target" >&2
    exit 1
  fi
  ujust hhd-setup
  mkdir -p -- "$plugins"
  if [[ ! -L "$target" ]]; then
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
