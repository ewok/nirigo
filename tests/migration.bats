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

gamescope_stubs() {
    export FP_USER=0 FP_SYSTEM=1 FP_STUCK=0
    # PID reported for Steam by `flatpak ps`; the test shell is always alive.
    export FP_PID=$$
    export FP_CALLS="$BATS_TEST_TMPDIR/flatpak.calls"
    export FP_RUNNING="$BATS_TEST_TMPDIR/steam.running"
    export GS_CALLS="$BATS_TEST_TMPDIR/gamescope.calls"
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    cat >"$BATS_TEST_TMPDIR/bin/flatpak" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FP_CALLS"
case "$1 $2" in
    'info --user') [[ $FP_USER == 1 ]] ;;
    'info --system') [[ $FP_SYSTEM == 1 ]] ;;
    'ps --columns=application')
        [[ -e $FP_RUNNING ]] && echo com.valvesoftware.Steam
        echo org.example.Other
        ;;
    'ps --columns=application,pid')
        [[ -e $FP_RUNNING ]] && echo "com.valvesoftware.Steam $FP_PID"
        echo "org.example.Other $$"
        ;;
    run\ *)
        if [[ ${*: -1} == -shutdown && $FP_STUCK != 1 ]]; then rm -f "$FP_RUNNING"; fi
        ;;
esac
SH
    cat >"$BATS_TEST_TMPDIR/bin/gamescope" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GS_CALLS"
SH
    printf '#!/usr/bin/env bash\n:\n' >"$BATS_TEST_TMPDIR/bin/sleep"
    printf '#!/usr/bin/env bash\n:\n' >"$BATS_TEST_TMPDIR/bin/notify-send"
    chmod +x "$BATS_TEST_TMPDIR"/bin/{flatpak,gamescope,sleep,notify-send}
}

@test "gamescope wrapper runs system Steam nested at native resolution" {
    gamescope_stubs
    run bash "$repo/files/system/usr/libexec/nirigo-gamescope-steam"
    [ "$status" -eq 0 ]
    [ "$(cat "$GS_CALLS")" = "-W 2560 -H 1600 -r 144 -f -- flatpak run --system com.valvesoftware.Steam -gamepadui -steamos3 -steampal -steamdeck" ]
}

@test "direct launcher runs Steam without gamescope or Deck flags" {
    gamescope_stubs
    touch "$FP_RUNNING"
    mkdir -p "$XDG_CONFIG_HOME/nirigo"
    echo 'NIRIGO_STEAM_ARGS=(-gamepadui -steamos3 -steampal -steamdeck)' >"$XDG_CONFIG_HOME/nirigo/gamescope.conf"
    rm "$BATS_TEST_TMPDIR/bin/gamescope"
    run bash "$repo/files/system/usr/libexec/nirigo-gamescope-steam" --direct
    [ "$status" -eq 0 ]
    [ "$(tail -n1 "$FP_CALLS")" = "run --system com.valvesoftware.Steam -gamepadui" ]
    run grep -c -- '-shutdown' "$FP_CALLS"
    [ "$output" = 0 ]
    [ ! -e "$GS_CALLS" ]
}

@test "gamescope wrapper prefers user Steam and uses session flags" {
    gamescope_stubs
    export FP_USER=1
    run bash "$repo/files/system/usr/libexec/nirigo-gamescope-steam" --session
    [ "$status" -eq 0 ]
    [ "$(cat "$GS_CALLS")" = "-W 2560 -H 1600 -r 144 -e --adaptive-sync -- flatpak run --user com.valvesoftware.Steam -gamepadui" ]
}

@test "gamescope wrapper stops when Steam is missing or arguments are wrong" {
    gamescope_stubs
    export FP_SYSTEM=0
    run bash "$repo/files/system/usr/libexec/nirigo-gamescope-steam"
    [ "$status" -eq 1 ]
    [[ $output == *'Steam is not installed'* ]]
    [ ! -e "$GS_CALLS" ]
    run bash "$repo/files/system/usr/libexec/nirigo-gamescope-steam" --bogus
    [ "$status" -eq 2 ]
    [ ! -e "$GS_CALLS" ]
}

@test "gamescope wrapper shuts down a running Steam first" {
    gamescope_stubs
    touch "$FP_RUNNING"
    run bash "$repo/files/system/usr/libexec/nirigo-gamescope-steam"
    [ "$status" -eq 0 ]
    grep -qx 'run --system com.valvesoftware.Steam -shutdown' "$FP_CALLS"
    [ -s "$GS_CALLS" ]
}

@test "gamescope wrapper ignores stale Steam rows with dead PIDs" {
    gamescope_stubs
    touch "$FP_RUNNING"
    true &
    FP_PID=$!
    wait "$FP_PID"
    export FP_PID
    run bash "$repo/files/system/usr/libexec/nirigo-gamescope-steam"
    [ "$status" -eq 0 ]
    [ -s "$GS_CALLS" ]
    run grep -c -- '-shutdown' "$FP_CALLS"
    [ "$output" = 0 ]
}

@test "gamescope wrapper gives up when Steam does not exit" {
    gamescope_stubs
    export FP_STUCK=1
    touch "$FP_RUNNING"
    mkdir -p "$XDG_CONFIG_HOME/nirigo"
    echo 'NIRIGO_STEAM_SHUTDOWN_TIMEOUT=2' >"$XDG_CONFIG_HOME/nirigo/gamescope.conf"
    run bash "$repo/files/system/usr/libexec/nirigo-gamescope-steam"
    [ "$status" -eq 1 ]
    [[ $output == *'still running'* ]]
    [ ! -e "$GS_CALLS" ]
}

@test "gamescope wrapper applies user overrides" {
    gamescope_stubs
    mkdir -p "$XDG_CONFIG_HOME/nirigo"
    cat >"$XDG_CONFIG_HOME/nirigo/gamescope.conf" <<'CONF'
NIRIGO_GAMESCOPE_ARGS=(-W 2560 -H 1600 -w 1920 -h 1200 -F fsr -r 144 -e)
NIRIGO_GAMESCOPE_NESTED_ARGS=()
NIRIGO_STEAM_ARGS=(-gamepadui -silent)
NIRIGO_STEAM_NESTED_ARGS=(-steamos3)
CONF
    run bash "$repo/files/system/usr/libexec/nirigo-gamescope-steam"
    [ "$status" -eq 0 ]
    [ "$(cat "$GS_CALLS")" = "-W 2560 -H 1600 -w 1920 -h 1200 -F fsr -r 144 -e -- flatpak run --system com.valvesoftware.Steam -gamepadui -silent -steamos3" ]
}

@test "gamescope entry points are executable and wired together" {
    [ -x "$repo/files/system/usr/libexec/nirigo-gamescope-steam" ]
    [ -x "$repo/files/system/usr/libexec/nirigo-gamescope-session" ]
    [ -x "$repo/files/scripts/install-gamescope.sh" ]
    grep -qx 'Exec=/usr/libexec/nirigo-gamescope-session' "$repo/files/system/usr/share/wayland-sessions/steam-gamescope.desktop"
    grep -qx 'Exec=/usr/libexec/nirigo-gamescope-steam --direct' "$repo/files/system/usr/share/applications/steam-gamescope.desktop"
    grep -q 'match app-id="steam" title="^Steam Big Picture Mode\$"' "$repo/files/system/usr/etc/niri/config.d/20-window-rules.kdl"
    grep -q 'exec /usr/libexec/nirigo-gamescope-steam --session' "$repo/files/system/usr/libexec/nirigo-gamescope-session"
    grep -q 'install-gamescope.sh' "$repo/recipes/recipe.yml"
    grep -q 'com.valvesoftware.Steam' "$repo/recipes/recipe.yml"
}

@test "hid-lenovo-go stays off the Legion Go controller so HHD touchpad works" {
    local conf="$repo/files/system/usr/lib/modprobe.d/nirigo-hid-lenovo-go.conf"
    grep -qx 'blacklist hid_lenovo_go' "$conf"
    grep -qx 'install hid_lenovo_go /bin/false' "$conf"
    # The initramfs is built before the files module, so dracut must omit it too.
    grep -q -- '--omit-drivers "hid-lenovo-go"' "$repo/files/scripts/installkernel.sh"
}

@test "HHD blacklist patch adds the missing continue and is idempotent" {
    local f="$BATS_TEST_TMPDIR/__main__.py"
    cat >"$f" <<'PY'
        for autodetect in entry_points(group="hhd.plugins"):
            name = autodetect.name
            detector_names.append(name)
            if name in blacklist:
                logger.info(f"Skipping blacklisted provider '{name}'.")
            if whitelist and name not in whitelist:
                continue
PY
    run bash "$repo/files/scripts/patch-hhd-blacklist.sh" "$f"
    [ "$status" -eq 0 ]
    grep -A1 "Skipping blacklisted provider" "$f" | grep -qx '                continue'
    run bash "$repo/files/scripts/patch-hhd-blacklist.sh" "$f"
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to do"* ]]
    [ "$(grep -c '^                continue$' "$f")" -eq 2 ]
}

@test "HHD blacklist patch stops the build when upstream code changed" {
    local f="$BATS_TEST_TMPDIR/__main__.py"
    printf 'something else\n' >"$f"
    run bash "$repo/files/scripts/patch-hhd-blacklist.sh" "$f"
    [ "$status" -ne 0 ]
    grep -q 'patch-hhd-blacklist.sh' "$repo/recipes/recipe.yml"
}
