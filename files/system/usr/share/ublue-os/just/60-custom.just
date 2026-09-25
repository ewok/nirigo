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
