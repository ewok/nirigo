# Niri on Legion Go

Image based on [Wayblue project](https://github.com/wayblueorg/wayblue) with some tweaks.

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

Pick the **Niri** session in SDDM on the next login. If something goes wrong you
can always `rpm-ostree rollback`, or rebase back to `ghcr.io/ewok/swaygo:latest`.

Then wire the drop-ins into your niri config (see below) and re-check your
personal keybinds: niri is a scrollable-tiling compositor, so the sway layout
bindings have no 1:1 equivalent.

## Niri configuration

niri only reads **one** config file: `~/.config/niri/config.kdl` if it exists,
otherwise `/etc/niri/config.kdl`. Unlike sway there is no automatic
`config.d/*` glob, so this image ships its Legion Go tweaks as explicit
includes:

| Path | Purpose |
| --- | --- |
| `/etc/niri/config.d/10-input.kdl` | Touchpad tap + natural scroll, touchscreen → built-in panel, power key left to logind |
| `/etc/niri/config.d/20-window-rules.kdl` | Float picture-in-picture players |
| `/etc/niri/config.d/30-session.kdl` | Start gnome-keyring / kwallet, like the wayblue sway image did |
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
* **`sway/mode` and `sway/scratchpad` waybar modules** — niri has neither;
  the bar now uses `niri/workspaces` and `niri/window`.
* **squeekboard on-screen keyboard** — not packaged in Fedora any more; the
  `XF86Launch6`/`XF86Launch7` bindings and the `us_wide.yaml` layout were
  removed.

### Screen sharing caveat

niri's `niri-portals.conf` prefers `xdg-desktop-portal-gnome`, which wayblue
does not install (it ships `xdg-desktop-portal-wlr` and `-gtk`). Screen sharing
and the waybar `privacy` module may therefore not work out of the box. Fix it
either by installing `xdg-desktop-portal-gnome`, or by dropping a
`/etc/xdg/xdg-desktop-portal/niri-portals.conf` that points ScreenCast at
`wlr`.

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
and the **swaylock screen lock**. SDDM login, `sudo` and polkit deliberately
stay password-only.

| Package | Use |
| --- | --- |
| `pam-u2f` | `pam_u2f.so`, used by `/etc/pam.d/swaylock` |
| `pamu2fcfg` | Registers a key into a mapping file |
| `fido2-tools` | `fido2-token`, to set or change the token PIN |
| `yubikey-manager` | `ykman`, general key management |

`systemd-cryptenroll` and `systemd-cryptsetup` come from the `systemd` package;
Fedora has no separate `systemd-cryptsetup` subpackage, and `libfido2` is
already in the base image as a dependency of `openssh-clients`.

### Screen lock

`/etc/pam.d/swaylock` is already configured:

```
auth sufficient   pam_u2f.so cue
auth include      login
```

`sufficient` means the key unlocks the screen on its own, and a failed or
missing key falls through to the normal password prompt. Register your key
first, otherwise `pam_u2f` has nothing to match against:

```
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

wayblue installs `swaylock` and `swayidle` for the niri image but wires up
neither — its sway and hyprland images ship a config, niri got nothing — so
stock wayblue niri suspends straight to an unlocked session.

This image adds `nirigo-swayidle.service`, a user unit enabled for all users:

```
/usr/bin/swayidle -w before-sleep '/usr/bin/swaylock -f'
```

`-w` is the entire point. swayidle takes a logind *delay* inhibitor and blocks
until `swaylock -f` reports the screen locked before releasing it, so the lock
is guaranteed to be up before the machine sleeps. Without it the suspend races
the locker.

`/etc/systemd/logind.conf.d/inhibit-delay.conf` raises `InhibitDelayMaxSec` from
its 5 s default to 10 s. Once that cap elapses logind suspends regardless, so a
slow locker on a loaded handheld would otherwise leave you resuming unlocked.

Check it is running with `systemctl --user status nirigo-swayidle.service`.

Only lock-on-suspend is configured. If you also want an idle timeout, or want
`loginctl lock-session` to actually do something (swaylock itself ignores
logind's `Lock` signal, so without a swayidle handler that command is a no-op),
drop in your own unit or extend the command line:

```
swayidle -w \
    timeout 300 'swaylock -f' \
    timeout 360 'niri msg action power-off-monitors' \
    before-sleep 'swaylock -f' \
    lock 'swaylock -f' \
    unlock 'pkill -u "$USER" -USR1 swaylock'
```

## Keyring

`gnome-keyring` is installed and `/etc/niri/config.d/30-session.kdl` starts it
with `gnome-keyring-daemon --start --components=secrets`. That spawn is not
redundant: PAM starts `gnome-keyring-daemon --login` at login, and that process
exits if nothing connects it to the session bus within a few minutes.

Auto-unlock at login is handled by PAM, not by the compositor. Fedora's stock
`/etc/pam.d/sddm` already carries the two lines that do it:

```
-auth    optional  pam_gnome_keyring.so
-session optional  pam_gnome_keyring.so auto_start
```

Verify with `grep gnome_keyring /etc/pam.d/sddm /etc/pam.d/passwd`. The `auth`
module stashes the password you typed, the `session` module uses it to decrypt
the `login` keyring. **This only works if the `login` keyring password equals
your account password.** If they have drifted apart, open Seahorse, right-click
the `login` keyring and change its password to match. `pam_gnome_keyring` in
`/etc/pam.d/passwd` keeps them in sync afterwards.

> **Warning**
> Do not add `pam_u2f.so` as `sufficient` to `/etc/pam.d/sddm`. A FIDO2
> assertion is not a password, so `PAM_AUTHTOK` is never set and
> `pam_gnome_keyring` has nothing to unlock the keyring with — you would get a
> manual keyring prompt the first time any app asks for a secret. This is the
> same failure mode as fingerprint login. That is why SDDM on this image stays
> password-only. If you want the YubiKey at login anyway, add it as a
> `required` second factor *after* `password-auth`, not as `sufficient`.

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

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/ewok/nirigo
```
