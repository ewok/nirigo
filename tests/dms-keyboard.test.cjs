const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync, mkdtempSync, mkdirSync, writeFileSync, readlinkSync, readdirSync, rmSync, symlinkSync } = require('node:fs');
const { tmpdir } = require('node:os');
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
        -nG)
            [[ "$2" == desktop-user ]] || return 99
            printf '%s\\n' "\${TEST_MEMBERSHIPS:-desktop-user wheel ydotool}"
            ;;
        *) return 99 ;;
    esac
}
sudo() {
    if [[ "$*" == 'tee -a /etc/group' ]]; then
        local entry
        IFS= read -r entry
        printf 'group-write:%s\\n' "$entry" >&2
    fi
    printf 'sudo:%s\\n' "$*"
    [[ "$*" != "$TEST_FAIL" ]]
}
getent() {
    if [[ "$*" == '-s files group ydotool' ]]; then
        [[ "\${TEST_LOCAL_GROUP:-yes}" == yes ]] || return 2
    elif [[ "$*" != 'group ydotool' ]]; then
        return 99
    fi
    [[ "\${TEST_GROUP_MISSING:-no}" != yes ]] || return 2
    printf '%s\\n' 'ydotool:x:987:existing-user'
}
systemctl() { printf 'user-systemctl:%s\\n' "$*"; }
ujust() {
    printf 'ujust:%s\\n' "$*"
    [[ "$*" == dms-qml-cache-reset ]]
}
dms() {
    printf 'desktop-dms:%s\\n' "$*"
    [[ "$TEST_FAIL" != dms ]]
}
`;

function sandbox(callback) {
    const tmp = mkdtempSync(join(tmpdir(), 'keyboard-setup-'));
    try {
        const source = join(tmp, 'image plugin');
        const configHome = join(tmp, 'user config');
        const config = join(configHome, 'DankMaterialShell');
        const target = join(config, 'plugins/virtualKeyboard');
        mkdirSync(source);
        writeFileSync(join(source, 'plugin.json'), '{"id":"virtualKeyboard"}');
        const script = recipe.replaceAll('/usr/lib/', '${TEST_IMAGE}/usr/lib/')
            .replace('source=/usr/share/nirigo/dms-plugins/VirtualKeyboard', 'source="$TEST_SOURCE"');
        const run = (extra = {}) => spawnSync('bash', ['-c', mocks + script], {
            encoding: 'utf8',
            env: { ...process.env, TEST_IMAGE: join(repo, 'files/system'), TEST_SOURCE: source,
                XDG_CONFIG_HOME: configHome, TEST_FAIL: '', ...extra },
        });
        return callback({ run, source, config, target, tmp });
    } finally {
        rmSync(tmp, { recursive: true, force: true });
    }
}

function run(extra = {}) {
    return sandbox(({ run }) => run(extra));
}

test('keyboard setup links the bundled plugin without a registry install and explains activation', () => {
    const result = run();
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /sudo:usermod --append --groups ydotool desktop-user/);
    assert.match(result.stdout, /sudo:systemctl enable ydotool.service/);
    assert.match(result.stdout, /sudo:systemctl restart ydotool.service/);
    assert.match(result.stdout, /Linked the image-owned Virtual Keyboard/);
    assert.match(result.stdout, /ujust:dms-qml-cache-reset/);
    assert.doesNotMatch(result.stdout, /desktop-dms:/);
    assert.doesNotMatch(result.stdout, /sudo:dms/);
    assert.match(result.stdout, /Log out and back in/);
    assert.match(result.stdout, /enable Virtual Keyboard/);
});

test('one-shot cache reset removes only compiled QML and restores DMS on cleanup failures', () => {
    const resetRecipe = justfile.split('dms-qml-cache-reset:\n')[1].split('\n\n')[0]
        .split('\n').map(line => line.slice(2)).join('\n');
    for (const failure of ['', 'remove', '--user stop dms.service',
        '--user unset-environment QML_DISABLE_DISK_CACHE QML_IMPORT_TRACE']) {
        const tmp = mkdtempSync(join(tmpdir(), 'qml-reset-'));
        try {
            const cacheHome = join(tmp, 'cache with spaces');
            const cache = join(cacheHome, 'quickshell/qmlcache');
            mkdirSync(cache, { recursive: true });
            writeFileSync(join(cache, 'stale.qmlc'), 'old compiled code');
            const unrelated = join(cacheHome, 'quickshell/keep.txt');
            writeFileSync(unrelated, 'unrelated data');
            const script = mocks + `
systemctl() {
    printf 'systemctl:%s\\n' "$*"
    [[ "$*" != "$TEST_FAIL" ]]
}
rm() {
    [[ "$TEST_FAIL" != remove ]] || return 1
    command rm "$@"
}
` + resetRecipe;
            const run = (extra = {}) => spawnSync('bash', ['-c', script], {
                encoding: 'utf8',
                env: { ...process.env, XDG_CACHE_HOME: cacheHome, TEST_FAIL: failure, ...extra },
            });
            const result = run();
            assert.equal(result.status, failure ? 1 : 0, result.stderr);
            assert.equal(readFileSync(unrelated, 'utf8'), 'unrelated data');
            if (failure === 'remove' || failure === '--user stop dms.service') {
                assert.equal(readFileSync(join(cache, 'stale.qmlc'), 'utf8'), 'old compiled code');
            } else {
                assert.throws(() => readdirSync(cache), { code: 'ENOENT' });
            }
            if (failure !== '--user stop dms.service') {
                assert.match(result.stdout, /systemctl:--user start dms.service/);
            }
            if (!failure) {
                assert.match(result.stdout, /QML cache will rebuild normally/);
                assert.equal(run().status, 0); // Missing cache is harmless.
                for (const extra of [{ TEST_UID: '0' }, { XDG_CACHE_HOME: 'relative' }]) {
                    const rejected = run(extra);
                    assert.equal(rejected.status, 1);
                    assert.doesNotMatch(rejected.stdout, /systemctl:/);
                }
            }
        } finally {
            rmSync(tmp, { recursive: true, force: true });
        }
    }
});

test('keyboard setup rejects root and missing image configuration before changes', () => {
    for (const extra of [{ TEST_UID: '0' }, { TEST_IMAGE: '/nonexistent-nirigo-image' }]) {
        const result = run(extra);
        assert.equal(result.status, 1);
        assert.doesNotMatch(result.stdout, /sudo:|desktop-dms:/);
    }
});

test('keyboard setup stops on privilege and service failures', () => {
    for (const failure of [
        'usermod --append --groups ydotool desktop-user',
        'systemctl enable ydotool.service',
        'systemctl restart ydotool.service',
    ]) {
        const result = run({ TEST_FAIL: failure });
        assert.equal(result.status, 1, failure);
        assert.doesNotMatch(result.stdout, /Log out and back in/);
        assert.doesNotMatch(result.stdout, /Linked the image-owned/);
    }
});

test('fresh link and repeated setup work with spaces in config paths', () => sandbox(({ run, target, source, config }) => {
    assert.equal(run().status, 0);
    assert.equal(readlinkSync(target), source);
    assert.equal(run().status, 0);
    assert.equal(readlinkSync(target), source);
    assert.throws(() => readdirSync(join(config, 'plugin-backups')), { code: 'ENOENT' });
}));

test('migration preserves local directories, registry symlinks, metadata and DMS settings', () => {
    for (const kind of ['directory', 'symlink', 'dangling']) sandbox(({ run, target, config, source, tmp }) => {
        mkdirSync(join(config, 'plugins'), { recursive: true });
        const original = join(tmp, 'original plugin');
        if (kind === 'directory') {
            mkdirSync(target);
            writeFileSync(join(target, 'personal.qml'), 'keep');
        } else {
            if (kind === 'symlink') {
                mkdirSync(original);
                writeFileSync(join(original, 'personal.qml'), 'keep');
            }
            symlinkSync(original, target);
        }
        writeFileSync(`${target}.meta`, 'original metadata');
        writeFileSync(join(config, 'plugin_settings.json'), '{"keep":true}');
        const result = run();
        assert.equal(result.status, 0, result.stderr);
        assert.equal(readlinkSync(target), source);
        const backupRoot = join(config, 'plugin-backups');
        const backup = join(backupRoot, readdirSync(backupRoot)[0]);
        assert.equal(readFileSync(join(backup, 'virtualKeyboard.meta'), 'utf8'), 'original metadata');
        if (kind === 'directory') {
            assert.equal(readFileSync(join(backup, 'virtualKeyboard/personal.qml'), 'utf8'), 'keep');
        } else {
            assert.equal(readlinkSync(join(backup, 'virtualKeyboard')), original);
        }
        assert.equal(readFileSync(join(config, 'plugin_settings.json'), 'utf8'), '{"keep":true}');
        assert.equal(run().status, 0);
        assert.equal(readdirSync(backupRoot).length, 1);
    });
});

test('missing bundled plugin stops before privileged changes', () => sandbox(({ run, source, target }) => {
    rmSync(join(source, 'plugin.json'));
    const result = run();
    assert.equal(result.status, 1);
    assert.doesNotMatch(result.stdout, /sudo:/);
    assert.throws(() => readlinkSync(target), { code: 'ENOENT' });
}));

test('image-only group is copied with its original GID and members; local groups are preserved', () => {
    const imageOnly = run({ TEST_LOCAL_GROUP: 'no' });
    assert.equal(imageOnly.status, 0, imageOnly.stderr);
    assert.match(imageOnly.stderr, /group-write:ydotool:x:987:existing-user/);
    assert.match(imageOnly.stdout, /Verified persistent ydotool membership/);
    const local = run();
    assert.equal(local.status, 0, local.stderr);
    assert.doesNotMatch(local.stderr, /group-write:/);
});

test('missing group and failed copy stop before usermod', () => {
    for (const extra of [
        { TEST_GROUP_MISSING: 'yes' },
        { TEST_FAIL: 'tee -a /etc/group' },
    ]) {
        const result = run({ TEST_LOCAL_GROUP: 'no', ...extra });
        assert.notEqual(result.status, 0);
        assert.doesNotMatch(result.stdout, /sudo:usermod|desktop-dms:/);
    }
});

test('silent usermod no-op is detected without claiming success or starting services', () => {
    const result = run({ TEST_MEMBERSHIPS: 'desktop-user wheel' });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /still not a member of ydotool/);
    assert.doesNotMatch(result.stdout, /sudo:systemctl|desktop-dms:|Log out and back in/);
});

test('movable keyboard stays within screen bounds after dragging or rotation, including scaled layouts', () => {
    const qml = readFileSync(join(repo,
        'files/system/usr/share/nirigo/dms-plugins/VirtualKeyboard/FloatingKeyboardWindow.qml'), 'utf8');
    const body = qml.match(/function constrainPosition\(\) \{([\s\S]*?)\n    \}/)[1];
    const constrain = new Function('movable', 'width', 'height', body);
    const card = { x: 1200, y: 700, width: 1000, height: 400, scale: 1 };
    constrain(card, 1600, 900);
    assert.deepEqual([card.x, card.y], [600, 500]);
    // Rotate to a narrow display: preserve the visible card, not unscaled bounds.
    card.scale = 0.8;
    constrain(card, 800, 1280);
    assert.deepEqual([card.x, card.y], [0, 500]);
    card.x = -50;
    card.y = 2000;
    constrain(card, 800, 1280);
    assert.deepEqual([card.x, card.y], [0, 960]);
    constrain(card, 0, 0); // Surface temporarily unconfigured during a mode change.
    assert.deepEqual([card.x, card.y], [0, 0]);
    assert.doesNotThrow(() => constrain(null, 0, 0));
});
