#!/usr/bin/env bats
# Each Bats test deliberately has its own environment.
# shellcheck disable=SC2030,SC2031

setup() {
    repo="$(dirname "$BATS_TEST_DIRNAME")"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
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
    export FP_USER=0 FP_SYSTEM=1 FP_STUCK=0 GS_EXIT=0
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
exit "$GS_EXIT"
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

@test "gamescope wrapper propagates a gamescope failure" {
    gamescope_stubs
    export GS_EXIT=42
    run bash "$repo/files/system/usr/libexec/nirigo-gamescope-steam" --session
    [ "$status" -eq 42 ]
    [[ $output == *'gamescope exited with status 42'* ]]
}

@test "gamescope entry points are executable and wired together" {
    [ -x "$repo/files/system/usr/libexec/nirigo-gamescope-steam" ]
    [ -x "$repo/files/system/usr/libexec/nirigo-gamescope-session" ]
    [ -x "$repo/files/scripts/install-gamescope.sh" ]
    [ -x "$repo/files/scripts/install-inputplumber.sh" ]
    grep -qx 'Exec=/usr/libexec/nirigo-gamescope-session' "$repo/files/system/usr/share/wayland-sessions/steam-gamescope.desktop"
    grep -qx 'Exec=/usr/libexec/nirigo-gamescope-steam --direct' "$repo/files/system/usr/share/applications/steam-gamescope.desktop"
    grep -q 'match app-id="steam" title="^Steam Big Picture Mode\$"' "$repo/files/system/usr/etc/niri/config.d/20-window-rules.kdl"
    grep -q 'exec /usr/libexec/nirigo-gamescope-steam --session' "$repo/files/system/usr/libexec/nirigo-gamescope-session"
    grep -q 'install-gamescope.sh' "$repo/recipes/recipe.yml"
    grep -q 'terra-gamescope' "$repo/files/scripts/install-gamescope.sh"
    grep -q 'install-inputplumber.sh' "$repo/recipes/recipe.yml"
    grep -q 'inputplumber.service' "$repo/recipes/recipe.yml"
    grep -q 'com.valvesoftware.Steam' "$repo/recipes/recipe.yml"
    grep -q 'setsid gamescope' "$repo/files/system/usr/libexec/nirigo-gamescope-steam"
    grep -q 'flock -n' "$repo/files/system/usr/libexec/nirigo-gamescope-steam"
    grep -q 'ConditionPathExists=!/var/lib/nirigo/inputplumber-migrated' "$repo/files/system/usr/lib/systemd/system/nirigo-inputplumber-migrate.service"
}

@test "InputPlumber replaces HHD and restores the native Legion Go driver" {
    grep -q 'inputplumber' "$repo/files/scripts/install-inputplumber.sh"
    grep -q '50-legion_go.yaml' "$repo/files/scripts/install-inputplumber.sh"
    ! grep -q 'hhd' "$repo/recipes/recipe.yml"
    ! grep -q 'omit-drivers.*hid-lenovo-go' "$repo/files/scripts/installkernel.sh"
    [ ! -e "$repo/files/system/usr/lib/modprobe.d/nirigo-hid-lenovo-go.conf" ]
    [ -f "$repo/files/system/usr/lib/systemd/system/nirigo-inputplumber-migrate.service" ]
}
