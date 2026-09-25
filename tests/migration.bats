#!/usr/bin/env bats
# Each Bats test deliberately has its own environment.
# shellcheck disable=SC2030,SC2031

setup() {
    repo="$(dirname "$BATS_TEST_DIRNAME")"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export HHD_MODE=quiet HHD_FAIL=0 HHD_CALLS="$BATS_TEST_TMPDIR/calls"
    cat >"$BATS_TEST_TMPDIR/bin/hhdctl" <<'SH'
#!/usr/bin/env bash
if [[ $1 == get ]]; then
    printf 'tdp.lenovo.tdp.mode=%s\n' "$HHD_MODE"
else
    printf '%s\n' "$*" >>"$HHD_CALLS"
    exit "$HHD_FAIL"
fi
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/hhdctl"
}

@test "TDP query does not change the mode" {
    run bash "$repo/files/system/usr/libexec/rotatetdp.sh"
    [ "$status" -eq 0 ]
    [ "$output" = quiet ]
    [ ! -e "$HHD_CALLS" ]
}

@test "TDP rotation covers all four modes" {
    local pair
    for pair in quiet:balanced balanced:performance performance:custom custom:quiet; do
        export HHD_MODE="${pair%:*}"
        run bash "$repo/files/system/usr/libexec/rotatetdp.sh" rotate
        [ "$status" -eq 0 ]
        [ "$output" = "${pair#*:}" ]
        grep -qx "set tdp.lenovo.tdp.mode=${pair#*:}" "$HHD_CALLS"
    done
}

@test "a failed HHD write never reports success" {
    export HHD_FAIL=1
    run bash "$repo/files/system/usr/libexec/rotatetdp.sh" rotate
    [ "$status" -ne 0 ]
    [ "$output" != balanced ]
}

@test "unknown TDP modes and invalid arguments cannot change HHD" {
    export HHD_MODE=unknown
    run bash "$repo/files/system/usr/libexec/rotatetdp.sh" rotate
    [ "$status" -ne 0 ]
    [ ! -e "$HHD_CALLS" ]
    run bash "$repo/files/system/usr/libexec/rotatetdp.sh" unexpected
    [ "$status" -eq 2 ]
    [ ! -e "$HHD_CALLS" ]
}

@test "template drift and missing template stop the build" {
    printf 'changed template\n' >"$BATS_TEST_TMPDIR/template.kdl"
    run bash "$repo/files/scripts/check-niri-config-drift.sh" "$BATS_TEST_TMPDIR/template.kdl"
    [ "$status" -ne 0 ]
    [[ $output == *'niri template changed'* ]]
    run bash "$repo/files/scripts/check-niri-config-drift.sh" "$BATS_TEST_TMPDIR/missing.kdl"
    [ "$status" -ne 0 ]
}
