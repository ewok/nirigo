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

# Clear compiled QML once after plugin/image changes, keeping normal caching.
dms-qml-cache-reset:
  #!/usr/bin/env bash
  set -Eeuo pipefail
  if [[ $(id -u) == 0 ]]; then
    printf 'Run ujust dms-qml-cache-reset as your desktop user, without sudo.\n' >&2
    exit 1
  fi
  # Qt CacheLocation uses Quickshell's application name, not the DMS name.
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/qmlcache"
  if [[ "$cache" != /* ]]; then
    printf 'error: XDG_CACHE_HOME must be an absolute path.\n' >&2
    exit 1
  fi
  systemctl --user stop dms.service
  # Restore the shell even if cache removal or environment cleanup fails.
  trap 'systemctl --user start dms.service' EXIT
  rm -rf -- "$cache"
  systemctl --user unset-environment QML_DISABLE_DISK_CACHE QML_IMPORT_TRACE
  systemctl --user start dms.service
  trap - EXIT
  printf 'Cleared %s and restarted DMS. QML cache will rebuild normally.\n' "$cache"

# Grant socket access and link the image-owned, non-focusing keyboard.
dms-keyboard-setup:
  #!/usr/bin/env bash
  set -Eeuo pipefail
  if [[ $(id -u) == 0 ]]; then
    printf 'Run ujust dms-keyboard-setup as your desktop user, without sudo. It requests sudo when needed.\n' >&2
    exit 1
  fi
  if [[ ! -f /usr/lib/sysusers.d/nirigo-ydotool.conf || ! -f /usr/lib/systemd/user/dms.service.d/10-ydotool.conf ]]; then
    printf 'error: keyboard configuration is missing; update to an image with keyboard support first.\n' >&2
    exit 1
  fi
  source=/usr/share/nirigo/dms-plugins/VirtualKeyboard
  config="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell"
  target="$config/plugins/virtualKeyboard"
  if [[ ! -f "$source/plugin.json" ]]; then
    printf 'error: bundled keyboard is missing; update to an image with the focus fix first.\n' >&2
    exit 1
  fi
  sudo systemd-sysusers /usr/lib/sysusers.d/nirigo-ydotool.conf
  # rpm-ostree can store image groups in /usr/lib/group (NSS altfiles).
  # usermod needs a writable /etc/group entry, preserving the image's GID.
  if ! getent -s files group ydotool >/dev/null; then
    group_entry=$(getent group ydotool)
    printf '%s\n' "$group_entry" | sudo tee -a /etc/group >/dev/null
  fi
  user=$(id -un)
  sudo usermod --append --groups ydotool "$user"
  # Query account membership, not the current session's stale group list.
  memberships=$(id -nG "$user")
  if [[ " $memberships " != *" ydotool "* ]]; then
    printf 'error: %s is still not a member of ydotool; inspect getent group ydotool and /etc/group.\n' "$user" >&2
    exit 1
  fi
  printf 'Verified persistent ydotool membership for %s.\n' "$user"
  sudo systemctl daemon-reload
  sudo systemctl enable ydotool.service
  sudo systemctl restart ydotool.service
  systemctl --user daemon-reload
  mkdir -p -- "$config/plugins"
  if [[ ! -L "$target" || $(readlink -- "$target") != "$source" ]]; then
    if [[ -e "$target" || -L "$target" || -e "$target.meta" ]]; then
      mkdir -p -- "$config/plugin-backups"
      backup=$(mktemp -d "$config/plugin-backups/virtualKeyboard.XXXXXX")
      if [[ -e "$target" || -L "$target" ]]; then
        mv -- "$target" "$backup/virtualKeyboard"
      fi
      if [[ -e "$target.meta" ]]; then
        mv -- "$target.meta" "$backup/virtualKeyboard.meta"
      fi
      printf 'Saved previous plugin and metadata to %s\n' "$backup"
    fi
    ln -sT -- "$source" "$target"
  fi
  printf 'Linked the image-owned Virtual Keyboard (docked and movable focus fixes).\n'
  ujust dms-qml-cache-reset
  printf 'Log out and back in to apply group membership and the DMS socket environment.\n'
  printf 'In DMS Settings → Plugins, scan and enable Virtual Keyboard.\n'
  printf 'Add its widget to your DankBar layout for touchscreen access.\n'
  printf 'Toggle it with: dms ipc call virtualKeyboard toggle\n'

# Initialize one packaged HHD daemon and verify Legion Go TDP.
hhd-setup action="setup":
  #!/usr/bin/env bash
  set -Eeuo pipefail
  action={{quote(action)}}
  case "$action" in setup|fix) ;; *) printf 'Expected setup or fix.\n' >&2; exit 1 ;; esac
  if [[ $(id -u) == 0 ]]; then
    printf 'Run ujust hhd-setup as your desktop user, without sudo. It requests sudo when needed.\n' >&2
    exit 1
  fi
  user=$(id -un)
  # Modern HHD uses /etc/hhd and deprecates --user. Retain older package support.
  load_state=$(systemctl show hhd.service --property=LoadState --value)
  case "$load_state" in
    loaded) unit=hhd.service ;;
    not-found) unit="hhd@$user.service" ;;
    *) printf 'error: hhd.service has LoadState=%s; resolve its unit configuration first.\n' "$load_state" >&2; exit 1 ;;
  esac
  diagnostics() {
    printf 'Inspect HHD with: systemctl status %q\n' "$unit" >&2
    printf 'Read its logs with: sudo journalctl -b -u %q --no-pager -n 80\n' "$unit" >&2
    printf 'Inspect all instances with: systemctl list-units --all "hhd*.service"\n' >&2
  }
  trap 'status=$?; printf "error: command failed (exit %s): %s\n" "$status" "$BASH_COMMAND" >&2; diagnostics' ERR
  # Match daemon commands, not hhdctl, hhd-ui or these helper recipes.
  check_processes() {
    local allowed=${1:-0} processes status pid command
    if processes=$(pgrep -af '(^|/|[[:space:]])hhd([[:space:]]|$)'); then
      while read -r pid command; do
        if [[ "$pid" != "$allowed" ]]; then
          printf 'error: another HHD process remains: %s %s\nStop its owning service or manually launched daemon, then run ujust hhd-fix.\n' "$pid" "$command" >&2
          return 1
        fi
      done <<<"$processes"
    else
      status=$?
      [[ "$status" == 1 ]] || return "$status"
    fi
  }
  # HHD instances share the API socket and controller devices.
  active=$(systemctl list-units --all --plain --no-legend --no-pager --state=active,activating,reloading,deactivating 'hhd*.service')
  # A filtered list-unit-files returns 1 when nothing matches. Query all service
  # files, then filter locally so an empty HHD selection is not a fatal error.
  unit_files=$(systemctl list-unit-files --type=service --no-legend --no-pager)
  enabled=""
  while read -r other state _; do
    case "$other" in hhd.service|hhd@?*.service) ;; *) continue ;; esac
    case "$state" in enabled|enabled-runtime) enabled+="$other"$'\n' ;; esac
  done <<<"$unit_files"
  declare -A seen=()
  while read -r other _; do
    # Restrict repair to the daemon units, excluding unrelated hhd-prefixed services.
    case "$other" in hhd.service|hhd@?*.service) ;; *) continue ;; esac
    [[ -z ${seen[$other]:-} ]] || continue
    seen[$other]=1
    if [[ "$action" == fix ]]; then
      printf 'Stopping and disabling %s\n' "$other"
      sudo systemctl disable --now "$other"
    elif [[ "$other" != "$unit" ]]; then
      printf 'error: %s is active or enabled; run ujust hhd-fix to repair conflicting services.\n' "$other" >&2
      exit 1
    fi
  done <<<"$active
  $enabled"
  main_pid=$(systemctl show "$unit" --property=MainPID --value)
  if [[ "$action" == fix ]]; then main_pid=0; fi
  check_processes "$main_pid"
  if ! sudo systemctl enable --now "$unit"; then
    diagnostics
    exit 1
  fi
  # Type=simple may be active before the API and device plugins are ready.
  for ((attempt=0; attempt<15; attempt++)); do
    if systemctl is-active --quiet "$unit" && mode=$(sudo -n timeout 2s hhdctl get tdp.lenovo.tdp.mode --values 2>&1); then
      case "$mode" in
        quiet|balanced|performance|custom)
          main_pid=$(systemctl show "$unit" --property=MainPID --value)
          [[ "$main_pid" =~ ^[1-9][0-9]*$ ]]
          check_processes "$main_pid"
          systemctl is-active --quiet "$unit"
          printf 'HHD enabled and ready (%s). Current TDP profile: %s\n' "$unit" "$mode"
          exit 0
          ;;
      esac
    fi
    sleep 1
  done
  printf 'error: HHD did not provide a valid Legion Go TDP profile. Last response: %s\n' "${mode:-service not active}" >&2
  diagnostics
  exit 1

# Repair duplicate system daemon services while preserving settings and profiles.
hhd-fix:
  ujust hhd-setup fix

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
setup-luks-fido2-unlock pin="keep":
  #!/usr/bin/env bash
  sudo /usr/libexec/nirigo-luks-fido2 enroll {{quote(pin)}}

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
