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

@test "native Steam and Game Mode are wired without Flatpak Steam" {
    [ -x "$repo/files/scripts/install-gamescope.sh" ]
    [ -x "$repo/files/scripts/install-inputplumber.sh" ]
    [ -x "$repo/files/system/usr/libexec/os-session-select" ]
    [ -x "$repo/files/system/usr/libexec/nirigo-steam-migrate" ]
    [ ! -e "$repo/files/system/usr/share/wayland-sessions/steam-gamescope.desktop" ]
    grep -qx 'Exec=steam -gamepadui' "$repo/files/system/usr/share/applications/steam-gamescope.desktop"
    grep -q 'match app-id="steam" title="^Steam Big Picture Mode\$"' "$repo/files/system/usr/etc/niri/config.d/20-window-rules.kdl"
    grep -q 'install-gamescope.sh' "$repo/recipes/recipe.yml"
    grep -q 'terra-gamescope' "$repo/files/scripts/install-gamescope.sh"
    grep -q 'install-inputplumber.sh' "$repo/recipes/recipe.yml"
    grep -q 'inputplumber.service' "$repo/recipes/recipe.yml"
    grep -q 'gamescope-session-ogui-steam' "$repo/files/scripts/install-inputplumber.sh"
    grep -qx '"$DNF" -y remove cardwire' "$repo/files/scripts/install-inputplumber.sh"
    grep -q 'steamos-manager-powerstation' "$repo/files/scripts/install-inputplumber.sh"
    ! grep -q 'com.valvesoftware.Steam' "$repo/recipes/recipe.yml"
    grep -qx 'systemctl --user exit' "$repo/files/system/usr/libexec/os-session-select"
    grep -q 'flatpak uninstall' "$repo/files/system/usr/libexec/nirigo-steam-migrate"
    grep -q 'nirigo-steam-migrate.service' "$repo/recipes/recipe.yml"
    grep -q 'ConditionPathExists=!/var/lib/nirigo/native-steam-migrated' "$repo/files/system/usr/lib/systemd/system/nirigo-steam-migrate.service"
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

@test "SteamOS Manager TDP helper reads, sets, and wraps the advertised range" {
    state="$BATS_TEST_TMPDIR/tdp"
    printf '15\n' >"$state"
    export TDP_STATE="$state"
    cat >"$BATS_TEST_TMPDIR/bin/busctl" <<'SH'
#!/usr/bin/env bash
if [[ $2 == get-property ]]; then
    case "${*: -1}" in
        TdpLimit) printf 'u %s\n' "$(<"$TDP_STATE")" ;;
        TdpLimitMin) printf 'u 5\n' ;;
        TdpLimitMax) printf 'u 30\n' ;;
        PerformanceProfile) printf 's "custom"\n' ;;
    esac
elif [[ $2 == set-property ]]; then
    printf '%s\n' "${*: -1}" >"$TDP_STATE"
fi
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/busctl"
    run bash "$repo/files/system/usr/libexec/nirigo-tdp"
    [ "$status" -eq 0 ]
    [ "$output" = 15 ]
    run bash "$repo/files/system/usr/libexec/nirigo-tdp" profile
    [ "$status" -eq 0 ]
    [ "$output" = custom ]
    run bash "$repo/files/system/usr/libexec/nirigo-tdp" set 30
    [ "$status" -eq 0 ]
    [ "$output" = 30 ]
    run bash "$repo/files/system/usr/libexec/nirigo-tdp" rotate
    [ "$status" -eq 0 ]
    [ "$output" = 5 ]
    run bash "$repo/files/system/usr/libexec/nirigo-tdp" set 31
    [ "$status" -eq 1 ]
    [[ $output == *'between 5 and 30 W'* ]]
}

@test "SteamOS Manager TDP is installed, migrated, and exposed through DMS" {
    grep -q 'steamos-manager-powerstation' "$repo/files/scripts/install-inputplumber.sh"
    grep -q 'rpm --upgrade --nodeps' "$repo/files/scripts/install-inputplumber.sh"
    grep -q 'install policycoreutils' "$repo/files/scripts/install-inputplumber.sh"
    grep -q 'steamos-manager.service' "$repo/recipes/recipe.yml"
    grep -q 'nirigo-steamos-manager-migrate.service' "$repo/recipes/recipe.yml"
    grep -q 'ConditionPathExists=!/var/lib/nirigo/steamos-manager-migrated' "$repo/files/system/usr/lib/systemd/system/nirigo-steamos-manager-migrate.service"
    grep -q 'com.steampowered.SteamOSManager1.TdpLimit1' "$repo/files/system/usr/libexec/nirigo-tdp"
    grep -q '"\$tdp_interface" TdpLimit' "$repo/files/system/usr/libexec/nirigo-tdp"
    grep -q 'PerformanceProfile s custom' "$repo/files/system/usr/libexec/nirigo-steamos-manager-profile"
    grep -q 'ExecStartPost=/usr/libexec/nirigo-steamos-manager-profile' "$repo/files/system/usr/lib/systemd/user/steamos-manager.service.d/10-nirigo-tdp.conf"
    grep -q 'Mod+Ctrl+T' "$repo/files/system/usr/etc/niri/config.d/40-dms.kdl"
    grep -q 'dms-tdp-setup:' "$repo/files/system/usr/share/ublue-os/just/60-custom.just"
    [ -f "$repo/files/system/usr/share/nirigo/dms-plugins/LegionGoTdp/plugin.json" ]
    [ -f "$repo/files/system/usr/share/nirigo/dms-plugins/LegionGoTdp/qmldir" ]
    grep -q 'TdpService' "$repo/files/system/usr/share/nirigo/dms-plugins/LegionGoTdp/LegionGoTdp.qml"
    grep -q 'nirigo-tdp' "$repo/files/system/usr/share/nirigo/dms-plugins/LegionGoTdp/TdpService.qml"
}
