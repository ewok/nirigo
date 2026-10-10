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

# Flatpak Steam cannot see the host gamescope. Install the Flathub gamescope
# Vulkan layer matching Steam's runtime so `gamescope -- %command%` launch
# options work per game. Not needed for the Game Mode session, which wraps
# Steam with the image's gamescope. The "Steam (Big Picture)" launcher runs
# Steam without gamescope, so use this for per-game gamescope there.
steam-gamescope-layer:
  #!/usr/bin/env bash
  set -euo pipefail
  app=com.valvesoftware.Steam
  if flatpak info --user "$app" >/dev/null 2>&1; then
    scope=--user
  elif flatpak info --system "$app" >/dev/null 2>&1; then
    scope=--system
  else
    echo "error: $app is not installed." >&2
    exit 1
  fi
  runtime=$(flatpak info "$scope" --show-runtime "$app")
  branch=${runtime##*/}
  ref="runtime/org.freedesktop.Platform.VulkanLayer.gamescope/x86_64/$branch"
  echo "Installing $ref ($scope) for $app ($runtime)"
  flatpak install "$scope" -y flathub "$ref"
  echo "Done. Use launch options like: gamescope -W 2560 -H 1600 -r 144 -f -- %command%"

# Per-user overrides for /usr/libexec/nirigo-gamescope-steam.
gamescope-config:
  #!/usr/bin/env bash
  set -euo pipefail
  conf="${XDG_CONFIG_HOME:-$HOME/.config}/nirigo/gamescope.conf"
  if [[ -e "$conf" ]]; then
    echo "$conf already exists, not overwriting."
    exit 0
  fi
  mkdir -p "$(dirname "$conf")"
  cat >"$conf" <<'EOF'
  # Sourced by /usr/libexec/nirigo-gamescope-steam (bash syntax).
  # Uncomment and edit; unset arrays keep the image defaults.

  # Used by the Game Mode session and the nested mode
  # (`nirigo-gamescope-steam` without arguments).
  # Default: native Legion Go panel.
  #NIRIGO_GAMESCOPE_ARGS=(-W 2560 -H 1600 -r 144)

  # Example: render at 1920x1200 and upscale to the panel with FSR.
  #NIRIGO_GAMESCOPE_ARGS=(-W 2560 -H 1600 -w 1920 -h 1200 -F fsr -r 144)

  # Extra flags for nested gamescope inside niri.
  # Do not add -e (Steam integration) here: nested, it breaks mouse and
  # keyboard input in Steam.
  #NIRIGO_GAMESCOPE_NESTED_ARGS=(-f)

  # Extra flags for the "Steam (Game Mode)" session. -e enables Steam
  # integration (Quick Access menu, Performance panel, overlay). If the picture
  # is rotated, add --force-orientation left (or right).
  #NIRIGO_GAMESCOPE_SESSION_ARGS=(-e --adaptive-sync)

  # Steam arguments for the "Steam (Big Picture)" launcher (no gamescope).
  # Do not add the SteamOS flags here.
  #NIRIGO_STEAM_DIRECT_ARGS=(-gamepadui)

  # Arguments passed to Steam in nested and Game Mode.
  #NIRIGO_STEAM_ARGS=(-gamepadui)

  # Extra Steam arguments for nested gamescope. Without the SteamOS
  # flags Big Picture turns black after the startup animation. If it is still
  # black, append -cef-disable-gpu-compositing.
  #NIRIGO_STEAM_NESTED_ARGS=(-steamos3 -steampal -steamdeck)

  # Extra Steam arguments for the Game Mode session. Do not add the SteamOS
  # flags together with -e: Steam then fails to start.
  #NIRIGO_STEAM_SESSION_ARGS=()

  # Seconds to wait for an already running Steam to exit.
  #NIRIGO_STEAM_SHUTDOWN_TIMEOUT=20
  EOF
  echo "Wrote $conf"
