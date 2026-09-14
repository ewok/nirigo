#!/usr/bin/env bash

# Tell build process to exit if there are any errors.
set -oue pipefail

# Swaps the base image's signed Fedora kernel for Bazzite's handheld ("ogc")
# kernel, which carries the Legion Go / handheld patch set.
#
# RPMs come from ghcr.io/ublue-os/akmods:ogc-<fedora>, copied to
# /tmp/rpms/kernel by the containerfile module in recipes/recipe.yml.
# That image ships: kernel, kernel-core, kernel-modules, kernel-devel,
# kernel-devel-matched. Notably it has NO kernel-modules-core, so the stock
# subpackages have to be erased with --nodeps rather than swapped with
# `rpm-ostree override replace`.

find /tmp/rpms/kernel

QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(\d+\.\d+\.\d+)' | sed -E 's/kernel-//')"
INCOMING_KERNEL_VERSION="$(basename -s .rpm "$(ls /tmp/rpms/kernel/kernel-[0-9]*.rpm | grep -P 'kernel-(\d+\.\d+\.\d+)')" | sed -E 's/kernel-//')"

echo "Qualified kernel: $QUALIFIED_KERNEL"
echo "Incoming kernel version: $INCOMING_KERNEL_VERSION"

if [[ "$INCOMING_KERNEL_VERSION" == "$QUALIFIED_KERNEL" ]]; then
    echo "Kernel versions match, only replacing vmlinuz from kernel-cache."
    cd /tmp
    rpm2cpio /tmp/rpms/kernel/kernel-core-*.rpm | cpio -idmv
    cp ./lib/modules/*/vmlinuz /usr/lib/modules/*/vmlinuz
    cd /
    exit 0
fi

echo "Removing stock kernel packages."
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
        rpm --erase "$pkg" --nodeps
    fi
done

# rpm leaves behind unowned files (initramfs.img, modules.dep, ...). A second
# stale tree under /usr/lib/modules makes bootc/ostree fail with
# "multiple kernels found", so clear it out before installing.
rm -rf /usr/lib/modules

echo "Installing ogc kernel rpms from kernel-cache."
dnf -y install \
    /tmp/rpms/kernel/kernel-[0-9]*.rpm \
    /tmp/rpms/kernel/kernel-core-*.rpm \
    /tmp/rpms/kernel/kernel-modules-*.rpm \
    /tmp/rpms/kernel/kernel-devel-*.rpm

# The install.d hooks are neutered inside a container build, so build the
# initramfs for the new kernel explicitly.
NEW_KERNEL="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)"
echo "Regenerating initramfs for $NEW_KERNEL"
/usr/bin/dracut --no-hostonly --kver "$NEW_KERNEL" --reproducible -v --add ostree \
    -f "/lib/modules/$NEW_KERNEL/initramfs.img"
chmod 0600 "/lib/modules/$NEW_KERNEL/initramfs.img"
