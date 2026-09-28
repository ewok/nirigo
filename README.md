# Niri on Legion Go

Fedora Atomic image based on [Wayblue](https://github.com/wayblueorg/wayblue),
with niri, Quickshell and DankMaterialShell (DMS). Login uses greetd with
DankGreeter. The handheld kernel, HHD and Legion Go input configuration are
included.

Added HHD with managing TDP via acpi_call.

> **Note**
> This image used to be `swaygo` (built on `ghcr.io/wayblueorg/sway`). It now
> tracks `ghcr.io/wayblueorg/niri`. See [Migrating from swaygo](#migrating-from-swaygo).

## Installation

> **Warning**
> [This is an experimental feature](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable), try at your own discretion.

To rebase an existing atomic Fedora installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:
  ```
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/ewok/nirigo:latest
  ```
- Reboot to complete the rebase:
  ```
  systemctl reboot
  ```
- Then rebase to the signed image, like so:
  ```
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ewok/nirigo:latest
  ```
- Reboot again to complete the installation
  ```
  systemctl reboot
  ```

The `latest` tag will automatically point to the latest build. That build will still always use the Fedora version specified in `recipe.yml`, so you won't get accidentally updated to the next major version.

## Migrating from swaygo

`swaygo` and `nirigo` are separate images, so the switch is a normal rebase:

```
rpm-ostree rebase ostree-unverified-registry:ghcr.io/ewok/nirigo:latest
systemctl reboot
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ewok/nirigo:latest
systemctl reboot
```

Pick the **Niri** session in DankGreeter on the next login. If something goes wrong you
can always `rpm-ostree rollback`, or rebase back to `ghcr.io/ewok/swaygo:latest`.

Then wire the drop-ins into your niri config (see below) and re-check your
personal keybinds: niri is a scrollable-tiling compositor, so the sway layout
bindings have no 1:1 equivalent.

## Migrating from the Waybar version of nirigo

The image now replaces Waybar, swaybg, dunst, the launchers, xfce-polkit,
swaylock and swayidle with DMS. SDDM is replaced by greetd/DankGreeter.
Audio/network/Bluetooth helper applications remain available.

Personal `~/.config/niri/config.kdl` files are not overwritten by image updates.
After updating, run `ujust dms-setup` to back up your personal config and adopt
the new defaults, then log out and back in. Reapply personal changes from the
printed backup path. Alternatively, merge manually: remove old shell startup
commands and bindings, remove the manual xwayland-satellite spawn and `DISPLAY`,
and include `/etc/niri/nirigo.kdl`. Appending the include alone does not remove
old startup commands. Review any personal systemd or XDG autostart entries too.

For locally modified `/etc` files, OSTree may preserve the old version: compare
`/etc/niri/config.kdl` with `/usr/etc/niri/config.kdl` before running the helper.
If the display-manager alias still points to SDDM after an upgrade, run
`sudo systemctl enable --force greetd.service` and reboot.

| Shortcut | Action |
| --- | --- |
| Mod+T | Ghostty |
| Mod+D / Mod+Space | DMS launcher |
| Mod+V / Mod+M / Mod+Comma | Clipboard / processes / settings |
| Mod+N / Mod+Y | Notifications / wallpapers |
| Super+Alt+L | Lock |
| Mod+Ctrl+T | Rotate HHD TDP mode and notify |
| Mod+Ctrl+V | Toggle floating (moved from Mod+V) |
| Mod+Ctrl+M | Maximize to edges (moved from Mod+M) |
| Mod+Ctrl+Comma | Consume window into column (moved from Mod+Comma) |

After login, `ujust dms-greeter-sync` optionally synchronizes the login theme.
The image configures greetd itself; do not run `dms-greeter install/enable` on
this Atomic image. Password login preserves keyring auto-unlock.

### Verification after updating

Check `systemctl status greetd`, `getent passwd greeter`,
`systemctl --user status dms`, and `niri validate`. Test touchscreen login,
notifications, polkit prompts, an X11 app, TDP rotation, lock/unlock and
lock-before-suspend on the device. Test browser screen sharing and keyring
auto-unlock. For greeter failures inspect `journalctl -b -u greetd` and
`sudo ausearch -m avc -ts recent` for SELinux denials.
The previous deployment can be selected in the boot menu or restored with
`rpm-ostree rollback`. Inspect `ostree admin status` before choosing which
deployment index to pin with `sudo ostree admin pin INDEX`.

## Niri configuration

`files/system/usr/etc/niri/config.kdl` is based on the Fedora 44 niri
26.04 stock template. `check-niri-config-drift.sh` fails the image build when
the packaged template checksum changes. Review the new upstream template,
update the fork and its provenance, then update the checksum in that script.
The include chain is validated during every image build. Niri starts
xwayland-satellite on demand; do not manually spawn it or force `DISPLAY`.

niri only reads **one** config file: `~/.config/niri/config.kdl` if it exists,
otherwise `/etc/niri/config.kdl`. Unlike sway there is no automatic
`config.d/*` glob, so this image ships its Legion Go tweaks as explicit
includes:

| Path | Purpose |
| --- | --- |
| `/etc/niri/config.d/10-input.kdl` | Touchpad tap + natural scroll, touchscreen → built-in panel, power key left to logind |
| `/etc/niri/config.d/20-window-rules.kdl` | Float picture-in-picture players |
| `/etc/niri/config.d/30-session.kdl` | Start the GNOME Keyring secret service |
| `/etc/niri/config.d/40-dms.kdl` | Shell shortcuts, clipboard history and wallpaper layers |
| `/etc/niri/nirigo.kdl` | Generated aggregate that includes all of the above |

`/etc/niri/config.kdl` already includes `nirigo.kdl`, so the defaults work out
of the box. If you use your own `~/.config/niri/config.kdl`, add one line to it:

```kdl
include "/etc/niri/nirigo.kdl"
```

Includes are positional in niri, so place it where you want these settings to
take effect relative to your own. There is a helper for this:

```
ujust niri-init-config
```

It appends the include to an existing `~/.config/niri/config.kdl`, or seeds one
from `/etc/niri/config.kdl` if you don't have one yet.

### Touchscreen output name

`10-input.kdl` maps the touchscreen with:

```kdl
input {
    touch {
        map-to-output "Lenovo Group Limited Go Display 0x00888888"
    }
}
```

Confirm the name on your device with `niri msg outputs` — niri accepts either
the connector name (`eDP-1`) or `"<make> <model> <serial>"`.

### Things that did not survive the move from sway

* **Window marks** — niri has no equivalent, so `mark Browser` is gone.
* **Sticky windows** — niri floating windows live on a single workspace, so
  picture-in-picture is floated but no longer follows you across workspaces.
* **`sway/mode` and `sway/scratchpad` modules** — niri has neither;
  DMS now provides the bar and workspace display.
* **squeekboard on-screen keyboard** — not packaged in Fedora any more; the
  `XF86Launch6`/`XF86Launch7` bindings and the `us_wide.yaml` layout were
  removed.

### Screen sharing

The image installs `xdg-desktop-portal-gnome` and selects it for ScreenCast
and Screenshot in `/etc/xdg/xdg-desktop-portal/niri-portals.conf`. Niri uses
the GNOME screencast integration; the wlr backend is not a substitute.
The Secret portal remains assigned to `gnome-keyring`.

## Filesystems (FUSE)

The base image already covers most of this: `fuse3`, `fuse-overlayfs` and the
full gvfs stack (`gvfs-mtp`, `gvfs-gphoto2`, `gvfs-smb`, `gvfs-nfs`) ship with
wayblue, so phones and cameras mount in Thunar over USB without any extra
setup. On top of that this image adds:

| Package | Use |
| --- | --- |
| `fuse-sshfs` | `sshfs user@host:/path ~/mnt/host` |
| `rclone` | `rclone mount remote: ~/mnt/remote` for Drive/S3/B2/… |
| `gocryptfs` | Encrypted directories, e.g. `gocryptfs ~/.vault ~/vault` |
| `fuse` / `fuse-libs` (v2) | AppImage mount helper and `libfuse.so.2` |

`/etc/fuse.conf` sets `user_allow_other` so `-o allow_other` /
`--allow-other` work without root.

Two things to keep in mind on an ostree system:

* **Mount somewhere writable.** `/usr` is read-only and sealed by composefs.
  Use `$HOME`, `/var/mnt` or `/run/media`.
* **Flatpaks and SELinux.** FUSE mounts are labelled `fusefs_t`, which
  sandboxed Flatpak apps often cannot read even with `--filesystem=home`. Native
  packages and distrobox are unaffected.

FUSE v2 is layered back in deliberately — Fedora Atomic
[drops it by default](https://fedoraproject.org/wiki/Changes/AtomicDesktopDropFuse2).
If you would rather not have the setuid `fusermount` around, drop `fuse` from
`recipe.yml` and run AppImages with `--appimage-extract-and-run` instead.

## YubiKey

The YubiKey guards two things on this image: the **LUKS root volume at boot**
and, once enabled in DMS settings, the **DMS screen lock**. No YubiKey PAM
changes are applied to greetd login, `sudo` or polkit.

| Package | Use |
| --- | --- |
| `pam-u2f` | `pam_u2f.so`, used by `/etc/pam.d/dankshell-u2f` |
| `pamu2fcfg` | Registers a key into a mapping file |
| `fido2-tools` | `fido2-token`, to set or change the token PIN |
| `yubikey-manager` | `ykman`, general key management |

`systemd-cryptenroll` and `systemd-cryptsetup` come from the `systemd` package;
Fedora has no separate `systemd-cryptsetup` subpackage, and `libfido2` is
already in the base image as a dependency of `openssh-clients`.

### Screen lock

`/etc/pam.d/dankshell-u2f` supplies DMS's dedicated key-only service:

```
auth required pam_u2f.so cue origin=pam://nirigo appid=pam://nirigo
account required pam_permit.so
```

In **Settings → Lock Screen**, enable security-key authentication and select
**OR** for password-or-key unlocking. The Auto security-key source discovers
this file; the password service is separate. Validate it with
`dms auth validate --purpose u2f --path /etc/pam.d/dankshell-u2f`.
Existing nirigo enrollment files can be reused. For a new enrollment:

```
mkdir -p ~/.config/Yubico
pamu2fcfg -u "$USER" -o pam://nirigo -i pam://nirigo > ~/.config/Yubico/u2f_keys
```

Set the origin and appid explicitly (as above) rather than relying on the
default `pam://$HOSTNAME` — the hostname can change on a DHCP network and the
key then stops matching.

### LUKS unlock at boot

```
ujust setup-luks-fido2-unlock
```

New enrollment requires **both** the token PIN and a physical touch by default.
Rerunning setup reuses an existing FIDO2 enrollment and retries verification and
boot configuration. Your existing LUKS passphrase remains the fallback.

To explicitly replace FIDO2 enrollment with **touch-only** unlock (no PIN):

```bash
ujust setup-luks-fido2-unlock no
```

To replace it with **PIN + touch** again:

```bash
ujust setup-luks-fido2-unlock yes
```

These policies require reenrollment; they do not change the YubiKey's global PIN.
Touch-only allows someone holding the key to unlock this disk without knowing a
PIN. Token policy may still require authentication during credential creation.

The recipe does four things the equivalent upstream scripts do not:

1. Enrolls a **recovery key first** and refuses to continue until you confirm
   you have copied it off the machine. Losing or resetting a YubiKey must not
   be able to cost you the volume.
2. **Verifies the FIDO2 key** with `cryptsetup open --test-passphrase --token-only
   --token-type systemd-fido2`, without creating a second mapping of the running
   root volume or accepting passphrase/TPM fallback. This requires `cryptsetup`
   and its systemd FIDO2 token plugin. If verification fails, enrollment remains
   on disk, but crypttab and the initramfs are untouched. Rerun setup to resume.
3. Writes a well-formed four-field `/etc/crypttab` line and keeps a backup at
   `/etc/crypttab.nirigo-fido2.bak`.
4. Uses `rpm-ostree initramfs-etc --track=/etc/crypttab` instead of
   `rpm-ostree initramfs --enable`, so no dracut run is added to every future
   upgrade.

That last point is the non-obvious part. dracut only copies `/etc/crypttab`
into the initramfs in *hostonly* mode, and this image builds its initramfs with
`--no-hostonly` (see `files/scripts/installkernel.sh`). The initrd therefore has
no crypttab at all and unlocks root purely from the `rd.luks.uuid=` kernel
argument — editing `/etc/crypttab` by hand does nothing for boot. `initramfs-etc`
injects the file and re-syncs it into every new deployment.

The dracut `fido2` module is already present: the base image ships
`ublue-os-luks`, which drops in
`/usr/lib/dracut/dracut.conf.d/90-ublue-luks.conf` with
`add_dracutmodules+=" fido2 tpm2-tss pkcs11 pcsc "`. The helper checks the initramfs
for libfido2 and the systemd FIDO2 token plugin. An inspection failure is reported
as unknown rather than as confirmed support.

To inspect or undo:

```
ujust luks-fido2-status
ujust remove-luks-fido2-unlock
```

Caveats:

* **Only single-volume setups.** The script refuses to guess if `/etc/crypttab`
  has more than one entry.
* **LUKS2 only.** `systemd-cryptenroll` stores its metadata in the LUKS2 JSON
  token area.
* **TPM2 wins.** If you have also run `ujust setup-luks-tpm-unlock` (from
  `ublue-os-just`), the TPM unlocks silently at boot and you will never be asked
  for the token. Remove one or the other.
* **Recovery.** If boot breaks, the passphrase prompt still works, and the
  previous deployment is one `rpm-ostree rollback` away.
* Only genuine FIDO2 authenticators work (YubiKey 5 / Bio / Security Key).
  U2F-only keys such as the YubiKey 4 series have no `hmac-secret` extension.

## Screen locking and suspend

DMS owns locking and idle policy through the enabled `dms.service` user unit.
The old `nirigo-swayidle.service` is retired and globally masked to prevent
stale enablement links from starting a second locker.

Use `dms ipc call lock lock` or Super+Alt+L to lock. In DMS settings verify
**loginctl lock integration** and **lock before suspend** are enabled, and
configure AC/battery idle timeouts there. Test a suspend/resume cycle before
relying on the new configuration. The power button still requests suspend
through logind, and `InhibitDelayMaxSec=10` remains configured.

## On-screen keyboard

The image includes `ydotool` and enables Fedora's system-level
`ydotool.service`. Its socket is `/run/ydotoold/socket`, owned by
`root:ydotool` with mode `0660`, inside a `0750` runtime directory. The DMS
user service receives `YDOTOOL_SOCKET=/run/ydotoold/socket` through an
image-owned systemd drop-in.

After updating and booting the image, run as your desktop user (without
`sudo`):

```bash
ujust dms-keyboard-setup
```

The helper requests sudo to add your user to the `ydotool` group and enable
and restart the daemon, then links the image-owned
[Virtual Keyboard plugin](https://github.com/sitolam/dms-plugins/tree/main/plugins/virtualkeyboard)
from `/usr/share/nirigo/dms-plugins/VirtualKeyboard`. The image downloads a
pinned upstream revision during its build and overlays nirigo's focus fixes.
User setup works offline, and keyboard updates follow image updates.

Rerun the helper to migrate an earlier registry installation. It moves the
existing `plugins/virtualKeyboard` directory or symlink and its `.meta` file
into a uniquely named directory under
`${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugin-backups/`, then
creates the image-owned link. Existing DMS plugin settings and widget IDs
are retained. Repeated setup leaves the correct link alone. The helper clears
the compiled QML cache and restarts DMS after linking the plugin. Use the bundled
copy rather than reinstalling the registry version, which lacks these fixes.

On-device testing found that cached QML continued loading the original,
focusable keyboard even though the symlink and installed sources were correct;
bypassing the disk cache made the patched keyboard work. To invalidate that
cache once after a plugin or image update, run as your desktop user:

```bash
ujust dms-qml-cache-reset
```

The keyboard setup helper calls this automatically. It stops DMS, removes
`${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/qmlcache`, clears the temporary
`QML_DISABLE_DISK_CACHE`/`QML_IMPORT_TRACE` service-manager settings, and starts
DMS again. Qt rebuilds the compiled QML cache normally; settings, downloaded
plugins, wallpapers and other caches are preserved. This cache directory is
shared by Quickshell configurations, not exclusive to DMS.

If you previously added `Environment=QML_DISABLE_DISK_CACHE=1` through
`systemctl --user edit dms.service`, remove that line and run
`systemctl --user daemon-reload` before resetting the cache. The helper does
not rewrite your personal service overrides.

On Fedora Atomic, image-provided groups can live in `/usr/lib/group` instead
of `/etc/group`. The helper copies the `ydotool` entry into the writable group
database when needed, preserving its GID and existing members, before calling
`usermod`. It verifies the saved membership with `id -nG <username>` and stops
if the change did not take effect.

If an older helper ran silently but `groups` still omits `ydotool` after a
reboot, repair the membership from a Bash terminal as your desktop user:

```bash
(
  set -euo pipefail
  if ! getent -s files group ydotool >/dev/null; then
    entry=$(getent group ydotool)
    printf '%s\n' "$entry" | sudo tee -a /etc/group >/dev/null
  fi
  sudo usermod --append --groups ydotool "$(id -un)"
  id -nG "$(id -un)"
)
```

The last command should show `ydotool` immediately: specifying the username
queries saved membership. Bare `groups` or `id -nG` show the running session's
groups, which only change after logging out and back in.

**Log out and back in** to apply group membership and the DMS environment.
In **Settings → Plugins**, enable **Virtual Keyboard**, then add its widget
under **Settings → DankBar** for touchscreen access. To toggle it from a
terminal or your own niri binding:

```bash
dms ipc call virtualKeyboard toggle
```

The plugin also supports `open` and `close`. It opens on demand rather than
automatically when a text field gains focus, and currently ships US QWERTY.
Test it by focusing a text editor and tapping keys on the keyboard widget.

Both keyboard modes use non-focusing Wayland layer-shell panels so tapping
keys leaves the application focused. The pin button switches to a movable
overlay: drag the handle above the keys with a finger or mouse. It stays
within its screen and scales down if needed to fit after display rotation.
It is an overlay, not a normal niri floating window; moving it to another
monitor using niri window commands is not supported. Closing and reopening
the movable keyboard resets its position near the bottom of the screen.

Use the on-screen hide button, DankBar toggle or IPC `close` to dismiss it.
Physical Escape goes to the focused application instead of closing the
keyboard. The daemon still releases latched modifiers on hide and pin/unpin.

On-device focus checks: type into an editor in both modes; drag the pinned
keyboard and type again; tap another application outside the keyboard and
verify subsequent keys reach it. Test Shift/Ctrl/Alt, hide/reopen, pin/unpin,
and display rotation while the keyboard is open. The surrounding transparent
area must remain clickable and must not cover other applications' input.

For diagnostics:

```bash
systemctl status ydotool.service
systemctl --user show dms.service -p Environment
id -nG
stat /run/ydotoold/socket
sudo journalctl -b -u ydotool.service --no-pager -n 80
```

The environment shown for DMS should include the socket path, and `id -nG`
should include `ydotool`. To test the client directly, focus a text editor
within three seconds of running this (it types `a`):

```bash
sleep 3; YDOTOOL_SOCKET=/run/ydotoold/socket ydotool key 30:1 30:0
```

## Legion Go TDP widget

The bundled **Legion Go TDP** plugin (DMS 1.6+) provides both a DankBar widget
and a Control Center tile. Initialize HHD and install the per-user link with
one command, run as your desktop user (without `sudo`):

```bash
ujust dms-tdp-setup
```

The helper calls `ujust hhd-setup`, which requests sudo to enable and start
the packaged `hhd.service` at boot (falling back to `hhd@<your-username>.service`
on older packages), then retries the TDP read for up to about 45 seconds.
It checks service health and competing daemon processes before reporting the
current profile. Failures print diagnostic commands. Both commands can be rerun;
`ujust hhd-setup` also works on its own when you only need the daemon.

If setup reports conflicting services, or a service's journal stops at
`Trying to acquire hhd lock...`, run as your desktop user:

```bash
ujust hhd-fix
```

This stops and disables active/enabled `hhd.service` and `hhd@…` system-service
instances, then starts the selected packaged service and verifies readiness.
Settings and profiles are preserved. Repeated repair runs are supported.
If another daemon remains (for example, a manually launched process or a user
service), repair stops and prints its PID and command; stop that daemon or its
owning service and rerun the helper. Repair interrupts HHD controller emulation
briefly. Verify touchpad movement on the device after repair; a successful TDP
read alone does not verify touchpad functionality.

In **Settings → Plugins**, scan for plugins and enable **Legion Go TDP**. Add
it to your DankBar layout and Control Center widgets, then run `dms restart`
if it does not appear. The link points to `/usr/share/nirigo/dms-plugins/LegionGoTdp`,
so plugin updates follow image updates. The helper respects `XDG_CONFIG_HOME`
and refuses to overwrite an existing local plugin.

Click or tap either surface to cycle **Quiet → Balanced → Performance → Custom
→ Quiet**. The horizontal bar shows the profile name; vertical bars use
**Q/B/P/C**. Right-click the bar widget to refresh immediately. Both surfaces
share state and refresh every five seconds while a widget instance is loaded,
including changes made with the existing keyboard shortcut or HHD.

The plugin calls `sudo -n /usr/libexec/rotatetdp.sh [rotate]` using the image's
existing sudoers rule. It displays profile names, not wattage. Failed reads
show **Unavailable**; failed switches show a DMS error toast. To diagnose:

```bash
sudo -n /usr/libexec/rotatetdp.sh
```

For development, link `files/system/usr/share/nirigo/dms-plugins/LegionGoTdp`
from your checkout into your DMS plugins directory instead, and restart DMS
after changing the shared QML singleton. On-device smoke checks: add both
surfaces, cycle all four profiles, change the profile through HHD, and verify
the unavailable state and recovery when HHD is stopped and restarted.

### HHD UI: `libfuse.so.2` missing

The upstream `hhd-ui` RPM installs an AppImage as `/usr/bin/hhd-ui`. Older
AppImage runtimes need the FUSE 2 library, `libfuse.so.2`, supplied by Fedora's
`fuse-libs`. FUSE 3 does not provide this ABI. The image recipe explicitly installs
both `fuse-libs` and `fuse` (the AppImage mount helper).
This UI dependency is separate from the HHD daemon/API socket.

Check the **booted host**, outside distrobox/toolbox:

```bash
rpm -q hhd-ui fuse fuse-libs
rpm -q --whatprovides 'libfuse.so.2()(64bit)'
rpm-ostree status
```

If the library is missing, update to a build containing the FUSE package and
reboot (`rpm-ostree upgrade`, then `systemctl reboot`). For an older image
without the library, `sudo rpm-ostree install fuse-libs` followed by a reboot
provides it. If the package is already installed but the error persists, check
`rpm -V fuse-libs` and `command -v hhd-ui` and capture the full launch error.
Enabling HHD alone cannot fix a missing AppImage library.

## Keyring

`gnome-keyring` is installed and `/etc/niri/config.d/30-session.kdl` starts it
with `gnome-keyring-daemon --start --components=secrets`. That spawn is not
redundant: PAM starts `gnome-keyring-daemon --login` at login, and that process
exits if nothing connects it to the session bus within a few minutes.

Auto-unlock at login is handled by PAM, not by the compositor. Fedora's stock
`/etc/pam.d/greetd` already carries the two lines that do it. The image ensures
`gnome-keyring-pam` is installed:

```
-auth    optional  pam_gnome_keyring.so
-session optional  pam_gnome_keyring.so auto_start
```

Verify with `grep gnome_keyring /etc/pam.d/greetd /etc/pam.d/passwd`. The `auth`
module stashes the password you typed, the `session` module uses it to decrypt
the `login` keyring. **This only works if the `login` keyring password equals
your account password.** If they have drifted apart, open Seahorse, right-click
the `login` keyring and change its password to match. `pam_gnome_keyring` in
`/etc/pam.d/passwd` keeps them in sync afterwards.

> **Warning**
> Do not add `pam_u2f.so` as `sufficient` to `/etc/pam.d/greetd`. A FIDO2
> assertion is not a password, so `PAM_AUTHTOK` is never set and
> `pam_gnome_keyring` has nothing to unlock the keyring with — you would get a
> manual keyring prompt the first time any app asks for a secret. This is the
> same failure mode as fingerprint login. Keep password authentication at
> login when automatic keyring unlocking is desired; lock-screen U2F is
> configured separately.

## Post-install

If you want to install Bazzite-arch in distrobox(to run Steam):

```
ujust install-bazzite-arch
```

To install nix:

```
ujust install-nix
```

## ISO

If build on Fedora Atomic, you can generate an offline ISO with the instructions available [here](https://blue-build.org/learn/universal-blue/#fresh-install-from-an-iso). These ISOs cannot unfortunately be distributed on GitHub for free due to large sizes, so for public projects something else has to be used for hosting.

## Verification

Local migration checks (requires Bats and ShellCheck):

```bash
bats tests/migration.bats
shellcheck files/scripts/check-niri-config-drift.sh files/scripts/remove-packages.sh \
  files/scripts/niri-dropins.sh files/system/usr/libexec/rotatetdp.sh tests/migration.bats
```

TDP plugin backend and TDP/keyboard setup-helper checks (requires Node.js):

```bash
node --test tests/dms-tdp.test.cjs tests/dms-keyboard.test.cjs
```

These exercise backend and setup logic with process doubles; QML loading,
socket access and UI behavior require the DMS/device smoke checks above.

The image build additionally checks the pinned stock template and runs
`niri validate` on both the assembled desktop config and the greeter config.
These checks do not replace the device smoke tests above.

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/ewok/nirigo
```
