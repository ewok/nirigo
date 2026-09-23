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
