#!/usr/bin/env bash

# Build HHD's ACPI interface for the image kernel, never the build host's kernel.
# installkernel.sh must run first to provide the matching kernel-devel package.
set -Eeuo pipefail

KERNEL="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)"
if [[ -z "$KERNEL" || "$KERNEL" == *$'\n'* || ! -d "/usr/src/kernels/$KERNEL" ]]; then
    printf 'Expected one installed kernel with matching headers; got: %s\n' "$KERNEL" >&2
    exit 1
fi

# Some kernel builds already provide the module. Preserve that copy if present.
if ! modinfo -k "$KERNEL" acpi_call >/dev/null 2>&1; then
    dnf -y install git gcc make binutils elfutils-libelf-devel openssl-devel kmod

    BUILD_DIR="$(mktemp -d /tmp/acpi-call.XXXXXX)"
    trap 'rm -rf -- "$BUILD_DIR"' EXIT

    # Pin the source so an upstream change cannot silently alter an image build.
    SOURCE_REVISION=6ad1e676dbfb5dcb1ec1f973c10ef5c57ffb4069
    git init "$BUILD_DIR"
    git -C "$BUILD_DIR" remote add origin https://github.com/nix-community/acpi_call.git
    git -C "$BUILD_DIR" fetch --depth=1 origin "$SOURCE_REVISION"
    git -C "$BUILD_DIR" checkout --detach FETCH_HEAD

    # Select the linker locally rather than modifying system alternatives.
    make -C "/usr/src/kernels/$KERNEL" M="$BUILD_DIR" LD=ld.bfd modules
    install -Dm0644 "$BUILD_DIR/acpi_call.ko" \
        "/usr/lib/modules/$KERNEL/extra/acpi_call/acpi_call.ko"
fi

depmod -a "$KERNEL"
VERMAGIC="$(modinfo -k "$KERNEL" -F vermagic acpi_call)"
if [[ "${VERMAGIC%% *}" != "$KERNEL" ]]; then
    printf 'acpi_call kernel mismatch: expected %s, got %s\n' "$KERNEL" "$VERMAGIC" >&2
    exit 1
fi
printf 'acpi_call is installed for %s\n' "$KERNEL"
