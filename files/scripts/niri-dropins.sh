#!/usr/bin/env bash

# Wire the nirigo niri drop-ins into an include chain, then validate the result.
#
# Background: sway auto-globbed /etc/sway/config.d/*, so dropping a file in
# there was enough. niri supports `include` (since 25.11) but has no glob
# support, so every drop-in has to be listed explicitly. This script generates
# that list into a single aggregate file, which means:
#
#   * the image's own /etc/niri/config.kdl picks the drop-ins up automatically,
#   * a user with their own ~/.config/niri/config.kdl (which makes niri ignore
#     /etc/niri/config.kdl entirely) only needs one stable line:
#
#         include "/etc/niri/nirigo.kdl"
#
# Tell build process to exit if there are any errors.
set -oue pipefail

# wayblue ships the niri system config under /usr/etc, which is what we see
# during the build. ostree merges /usr/etc into /etc when the image is
# deployed, so niri reads these same files from /etc at runtime.
BUILD_DIR="/usr/etc/niri"
RUNTIME_DIR="/etc/niri"

DROPIN_SUBDIR="config.d"
AGGREGATE_NAME="nirigo.kdl"

build_dropin_dir="${BUILD_DIR}/${DROPIN_SUBDIR}"
build_aggregate="${BUILD_DIR}/${AGGREGATE_NAME}"
runtime_aggregate="${RUNTIME_DIR}/${AGGREGATE_NAME}"
system_config="${BUILD_DIR}/config.kdl"

if [[ ! -d "${build_dropin_dir}" ]]; then
    echo "error: ${build_dropin_dir} does not exist." >&2
    echo "       This script must run after the 'files' module." >&2
    exit 1
fi

# Stable, locale-independent ordering, mirroring sway's config.d/* glob.
export LC_ALL=C
shopt -s nullglob
dropins=("${build_dropin_dir}"/*.kdl)
shopt -u nullglob

if [[ ${#dropins[@]} -eq 0 ]]; then
    echo "error: no *.kdl drop-ins found in ${build_dropin_dir}." >&2
    exit 1
fi

echo "Found ${#dropins[@]} niri drop-in(s):"
printf '  %s\n' "${dropins[@]}"

# Emit an aggregate file whose include paths are prefixed with $1.
generate_aggregate() {
    local prefix="$1"
    local dropin

    cat <<EOF
// Generated during the image build by files/scripts/niri-dropins.sh.
// Do not edit: your changes are overwritten on every build.
//
// Add this line to your own niri config to pick up the nirigo drop-ins:
//
//     include "${runtime_aggregate}"
//
// Includes are positional in niri, so put it wherever you want these settings
// to take effect relative to your own.
EOF

    for dropin in "${dropins[@]}"; do
        printf 'include "%s/%s"\n' "${prefix}" "$(basename "${dropin}")"
    done
}

generate_aggregate "${RUNTIME_DIR}/${DROPIN_SUBDIR}" >"${build_aggregate}"
echo "Wrote ${build_aggregate} (served as ${runtime_aggregate})"

# Make the image's default config pull the drop-ins in as well, so the image
# behaves correctly for users who have no config of their own.
if [[ -f "${system_config}" ]]; then
    if grep -qF "${runtime_aggregate}" "${system_config}"; then
        echo "${system_config} already includes ${runtime_aggregate}"
    else
        cat >>"${system_config}" <<EOF

// nirigo drop-ins. Appended during the image build; listed last so these
// settings win over the defaults above.
include "${runtime_aggregate}"
EOF
        echo "Appended include to ${system_config}"
    fi
else
    echo "warning: ${system_config} not found, only generated the aggregate." >&2
fi

# Fail the build on a broken drop-in instead of a broken login session. The
# include paths above point at /etc, which is not populated yet during the
# build, so validate against a temporary tree with rewritten paths.
if ! command -v niri >/dev/null 2>&1; then
    echo "warning: niri binary not found, skipping config validation." >&2
    exit 0
fi

tmpdir="$(mktemp -d)"
# shellcheck disable=SC2064 # expand tmpdir now, it never changes
trap "rm -rf '${tmpdir}'" EXIT

mkdir -p "${tmpdir}/${DROPIN_SUBDIR}"
cp "${dropins[@]}" "${tmpdir}/${DROPIN_SUBDIR}/"
generate_aggregate "${tmpdir}/${DROPIN_SUBDIR}" >"${tmpdir}/${AGGREGATE_NAME}"

if [[ -f "${system_config}" ]]; then
    sed "s|${runtime_aggregate}|${tmpdir}/${AGGREGATE_NAME}|g" \
        "${system_config}" >"${tmpdir}/config.kdl"
else
    cp "${tmpdir}/${AGGREGATE_NAME}" "${tmpdir}/config.kdl"
fi

echo "Validating ${tmpdir}/config.kdl with $(niri --version)"
HOME="${HOME:-/root}" niri validate --config "${tmpdir}/config.kdl"
echo "niri config validation passed."
