#!/usr/bin/env bash
# Hardware-free regression tests. No block devices or system files are touched.
set -euo pipefail
repo=$(dirname "$(dirname "$(realpath "$0")")")
# shellcheck source=../files/system/usr/libexec/nirigo-luks-fido2
source "$repo/files/system/usr/libexec/nirigo-luks-fido2"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

require_root() { :; }
require_ostree() { :; }
find_device() { printf '/mock/root\n'; }
luks_is_v2() { :; }
token_present() { :; }
enrolled_slots() { printf '0 password\n'; }
systemd-cryptenroll() {
    printf '%s\n' "$*" >>"$tmp/enroll"
    if [[ $# == 1 ]]; then
        printf '%s\n' "$mock_slots"
    fi
}
cryptsetup() {
    # Refuse any command that could activate a mapper or accept other methods.
    [[ "$*" == 'open --type luks2 --test-passphrase --token-only --token-type systemd-fido2 /mock/root' ]] || return 99
    printf 'verify\n' >>"$tmp/order"
    return "$verify_status"
}
crypttab_entry() { printf 'root UUID=mock none discard\n'; }
write_crypttab_options() { printf 'write\n' >>"$tmp/order"; }
sync_initramfs() { printf 'sync\n' >>"$tmp/order"; }
lsinitrd() {
    printf 'libfido2.so\nlibcryptsetup-token-systemd-fido2.so\n'
    # More than a pipe buffer, so early grep termination would expose SIGPIPE.
    for ((i=0; i<10000; i++)); do printf 'unrelated initramfs entry\n'; done
}
RECOVERY_FILE="$tmp/recovery"
printf 'mock recovery key\n' >"$RECOVERY_FILE"
mock_slots='2 fido2'
verify_status=0

(cmd_enroll <<<YES) >"$tmp/output" 2>&1
[[ $(<"$tmp/enroll") == /mock/root ]]
[[ $(<"$tmp/order") == $'verify\nwrite\nsync' ]]
printf 'PASS: existing enrollment resumes without replacement\n'

: >"$tmp/order"
verify_status=1
if (cmd_enroll <<<YES) >"$tmp/output" 2>&1; then
    printf 'FAIL: failed verification was accepted\n' >&2; exit 1
fi
[[ $(<"$tmp/order") == verify ]]
printf 'PASS: failed verification prevents boot configuration writes\n'

verify_status=0
for policy in yes no; do
    : >"$tmp/enroll"
    (cmd_enroll "$policy" <<<YES) >"$tmp/output" 2>&1
    grep -q -- "--wipe-slot=fido2 --fido2-device=auto --fido2-with-client-pin=$policy --fido2-with-user-presence=yes --fido2-with-user-verification=no /mock/root" "$tmp/enroll"
done
printf 'PASS: explicit PIN policies reenroll with touch required\n'

mock_slots='0 password'
: >"$tmp/enroll"
(cmd_enroll <<<YES) >"$tmp/output" 2>&1
grep -q -- '--fido2-with-client-pin=yes' "$tmp/enroll"
printf 'PASS: first enrollment defaults to PIN\n'

: >"$tmp/enroll"
if (cmd_enroll invalid) >"$tmp/output" 2>&1; then exit 1; fi
[[ ! -s "$tmp/enroll" ]]
printf 'PASS: invalid PIN policy rejected before enrollment\n'

initramfs_has_fido2
lsinitrd() { return 1; }
status=0
initramfs_has_fido2 || status=$?
[[ $status == 2 ]]
lsinitrd() { printf 'libfido2.so\n'; }
status=0
initramfs_has_fido2 || status=$?
[[ $status == 1 ]]
printf 'PASS: initramfs detection drains output and distinguishes unknown/missing\n'
