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
| `fuse` (v2) | `libfuse.so.2`, needed by AppImages |

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

This enrolls the token with `systemd-cryptenroll --fido2-device=auto`, which by
default requires **both** the token PIN and a physical touch. Your existing LUKS
passphrase is never removed and remains the fallback.

The recipe does four things the equivalent upstream scripts do not:

1. Enrolls a **recovery key first** and refuses to continue until you confirm
   you have copied it off the machine. Losing or resetting a YubiKey must not
   be able to cost you the volume.
2. **Proves the enrollment works offline** with `systemd-cryptsetup attach`
   before touching anything boot-critical. If that fails, nothing is changed.
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
`add_dracutmodules+=" fido2 tpm2-tss pkcs11 pcsc "`. The recipe verifies this
rather than assuming it.

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

The image build additionally checks the pinned stock template and runs
`niri validate` on both the assembled desktop config and the greeter config.
These checks do not replace the device smoke tests above.

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/ewok/nirigo
```
