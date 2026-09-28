const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { spawnSync } = require('node:child_process');

const repo = join(__dirname, '..');
const justfile = readFileSync(join(repo, 'files/system/usr/share/ublue-os/just/60-custom.just'), 'utf8');
const recipe = justfile.split('dms-keyboard-setup:\n')[1].split('\n\n')[0]
    .split('\n').map(line => line.slice(2)).join('\n');

// Mock privileged commands; exercise the actual recipe without touching the host.
const mocks = `
id() {
    case "$1" in
        -u) printf '%s\\n' "\${TEST_UID:-1000}" ;;
        -un) printf '%s\\n' 'desktop-user' ;;
        *) return 99 ;;
    esac
}
sudo() {
    printf 'sudo:%s\\n' "$*"
    [[ "$*" != "$TEST_FAIL" ]]
}
systemctl() { printf 'user-systemctl:%s\\n' "$*"; }
dms() {
    printf 'desktop-dms:%s\\n' "$*"
    [[ "$TEST_FAIL" != dms ]]
}
`;

function run(extra = {}) {
    return spawnSync('bash', ['-c', mocks + recipe.replaceAll('/usr/lib/', '${TEST_IMAGE}/usr/lib/')], {
        encoding: 'utf8',
        env: { ...process.env, TEST_IMAGE: join(repo, 'files/system'), TEST_FAIL: '', ...extra },
    });
}

test('keyboard setup keeps plugin installation unprivileged and explains activation', () => {
    const result = run();
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /sudo:usermod --append --groups ydotool desktop-user/);
    assert.match(result.stdout, /sudo:systemctl enable ydotool.service/);
    assert.match(result.stdout, /sudo:systemctl restart ydotool.service/);
    assert.match(result.stdout, /desktop-dms:plugins install virtualKeyboard/);
    assert.doesNotMatch(result.stdout, /sudo:dms/);
    assert.match(result.stdout, /Log out and back in/);
    assert.match(result.stdout, /enable Virtual Keyboard/);
});

test('keyboard setup rejects root and missing image configuration before changes', () => {
    for (const extra of [{ TEST_UID: '0' }, { TEST_IMAGE: '/nonexistent-nirigo-image' }]) {
        const result = run(extra);
        assert.equal(result.status, 1);
        assert.doesNotMatch(result.stdout, /sudo:|desktop-dms:/);
    }
});

test('keyboard setup stops on privilege, service and plugin installation failures', () => {
    for (const failure of [
        'usermod --append --groups ydotool desktop-user',
        'systemctl enable ydotool.service',
        'systemctl restart ydotool.service',
        'dms',
    ]) {
        const result = run({ TEST_FAIL: failure });
        assert.equal(result.status, 1, failure);
        assert.doesNotMatch(result.stdout, /Log out and back in/);
        if (failure !== 'dms') assert.doesNotMatch(result.stdout, /desktop-dms:/);
    }
});
