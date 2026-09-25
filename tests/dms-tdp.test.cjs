const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync, mkdtempSync, mkdirSync, writeFileSync, readlinkSync, symlinkSync, rmSync } = require('node:fs');
const { join } = require('node:path');
const { tmpdir } = require('node:os');
const { spawnSync } = require('node:child_process');
const vm = require('node:vm');

const repo = join(__dirname, '..');
const plugin = join(repo, 'files/system/usr/share/nirigo/dms-plugins/LegionGoTdp');

function setupRecipe(name) {
    const justfile = readFileSync(join(repo, 'files/system/usr/share/ublue-os/just/60-custom.just'), 'utf8');
    return justfile.match(new RegExp(`^${name}:\\n((?:  .*\\n)+)`, 'm'))[1].replace(/^  /gm, '');
}

function mockHhd(tmp) {
    const bin = join(tmp, 'bin');
    mkdirSync(bin);
    const scripts = {
        id: 'if [[ $1 == -u ]]; then printf "%s\\n" "${TEST_UID:-1000}"; else printf "gamer\\n"; fi',
        sudo: '[[ $1 == -n ]] && shift; exec "$@"',
        systemctl: `printf '%s\\n' "$*" >>"$TEST_LOG"
case "$1" in
    list-units) printf '%s\\n' "\${TEST_ACTIVE:-}" ;;
    list-unit-files) printf '%s\\n' "\${TEST_ENABLED:-}" ;;
    enable) exit "\${TEST_START_EXIT:-0}" ;;
    *) exit 99 ;;
esac`,
        hhdctl: `printf 'read\\n' >>"$TEST_LOG"
if [[ \${TEST_READ_EXIT:-0} != 0 ]]; then printf 'missing API\\n' >&2; exit "$TEST_READ_EXIT"; fi
printf '%s\\n' "\${TEST_MODE:-balanced}"`,
        sleep: ':',
        ujust: '[[ $1 == hhd-setup ]] || exit 99; exec bash "$TEST_HHD_RECIPE"',
    };
    for (const [name, body] of Object.entries(scripts)) {
        writeFileSync(join(bin, name), '#!/usr/bin/env bash\n' + body + '\n', { mode: 0o755 });
    }
    const recipe = join(tmp, 'hhd-setup.sh');
    writeFileSync(recipe, setupRecipe('hhd-setup'));
    return { ...process.env, PATH: `${bin}:${process.env.PATH}`, TEST_LOG: join(tmp, 'calls'), TEST_HHD_RECIPE: recipe };
}

// Exercise the actual backend methods with process/timer/toast doubles.
// QML bindings, imports and rendering still require an on-device smoke test.
function backend() {
    const source = readFileSync(join(plugin, 'TdpService.qml'), 'utf8');
    const methods = source.match(/^    function [\s\S]*?^    }/gm);
    const state = {
        consumers: 0, mode: '', error: '', busy: false, rotating: false,
        profiles: { quiet: { label: 'Quiet' }, balanced: { label: 'Balanced' },
            performance: { label: 'Performance' }, custom: { label: 'Custom' } },
        process: { running: false, command: [] },
        watchdog: { restart() {}, stop() {} },
        toasts: [],
    };
    state.ToastService = {
        showInfo: (...args) => state.toasts.push(['info', ...args]),
        showError: (...args) => state.toasts.push(['error', ...args]),
    };
    vm.createContext(state);
    vm.runInContext(methods.join('\n'), state);
    return state;
}

test('surfaces share one request and suppress overlapping clicks', () => {
    const b = backend();
    b.attach();
    const readCommand = b.process.command;
    b.attach();
    b.run(true);
    assert.equal(b.consumers, 2);
    assert.equal(b.process.command, readCommand);
    assert.equal(b.rotating, false);
    assert.equal(readCommand.at(-1), '/usr/libexec/rotatetdp.sh');
    b.detach();
    b.detach();
    assert.equal(b.consumers, 0);
});

test('all four successful switch results update the profile and notify', () => {
    for (const mode of ['quiet', 'balanced', 'performance', 'custom']) {
        const b = backend();
        b.run(true);
        assert.equal(b.process.command.at(-1), 'rotate');
        b.finish(0, mode + '\n', '');
        assert.equal(b.mode, mode);
        assert.equal(b.error, '');
        assert.equal(b.busy, false);
        assert.equal(b.toasts[0][0], 'info');
    }
});

test('failed writes and malformed output never report a successful switch', () => {
    for (const [code, output] of [[1, 'performance'], [0, 'unknown'], [0, ''], [-1, 'quiet']]) {
        const b = backend();
        b.mode = 'balanced';
        b.run(true);
        b.finish(code, output, 'HHD unavailable');
        assert.equal(b.mode, '');
        assert.equal(b.error, 'HHD unavailable');
        assert.equal(b.busy, false);
        assert.deepEqual(b.toasts, [['error', 'Legion Go TDP', 'HHD unavailable']]);
        b.finish(0, 'quiet', ''); // Ignore a late completion after timeout.
        assert.equal(b.mode, '');
    }
});

test('poll failures are silent and a later read recovers external state', () => {
    const b = backend();
    b.run(false);
    b.finish(1, '', 'offline');
    assert.equal(b.error, 'offline');
    assert.equal(b.toasts.length, 0);
    b.process.running = false;
    b.run(false);
    b.finish(0, 'custom\n', '');
    assert.equal(b.mode, 'custom');
    assert.equal(b.error, '');
    assert.equal(b.toasts.length, 0);
});

test('setup handles spaces, repeated installation and conflicting local plugins', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'tdp-setup-'));
    try {
        const source = join(tmp, 'image plugin');
        const config = join(tmp, 'user config');
        const target = join(config, 'DankMaterialShell/plugins/LegionGoTdp');
        mkdirSync(source);
        writeFileSync(join(source, 'plugin.json'), '{}');
        const env = mockHhd(tmp);
        const recipe = setupRecipe('dms-tdp-setup')
            .replace('source=/usr/share/nirigo/dms-plugins/LegionGoTdp', 'source="$TEST_SOURCE"');
        const run = (extra = {}) => spawnSync('bash', ['-c', recipe], {
            env: { ...env, XDG_CONFIG_HOME: config, TEST_SOURCE: source, ...extra }, encoding: 'utf8',
        });
        assert.equal(run({ TEST_START_EXIT: '1' }).status, 1);
        assert.throws(() => readlinkSync(target), { code: 'ENOENT' });
        assert.equal(run().status, 0);
        assert.equal(readlinkSync(target), source);
        assert.equal(run().status, 0);
        assert.match(readFileSync(env.TEST_LOG, 'utf8'), /enable --now hhd@gamer.service/);
        rmSync(target);
        mkdirSync(target);
        writeFileSync(join(target, 'personal.txt'), 'keep');
        assert.equal(run().status, 1);
        assert.equal(readFileSync(join(target, 'personal.txt'), 'utf8'), 'keep');
        rmSync(target, { recursive: true });
        symlinkSync(join(tmp, 'missing'), target);
        assert.equal(run().status, 1);
        assert.equal(readlinkSync(target), join(tmp, 'missing'));
        rmSync(source, { recursive: true });
        assert.equal(run().status, 1);
    } finally {
        rmSync(tmp, { recursive: true, force: true });
    }
});

test('HHD setup verifies readiness and diagnoses service, API and profile failures', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'hhd-setup-'));
    try {
        const env = mockHhd(tmp);
        const run = (extra = {}) => spawnSync('bash', [env.TEST_HHD_RECIPE], {
            env: { ...env, ...extra }, encoding: 'utf8',
        });
        assert.match(run().stdout, /Current TDP profile: balanced/);
        for (const extra of [{ TEST_START_EXIT: '1' }, { TEST_READ_EXIT: '1' }, { TEST_MODE: 'unknown' }]) {
            const result = run(extra);
            assert.equal(result.status, 1);
            assert.match(result.stderr, /journalctl -b -u hhd@gamer.service/);
        }
        const calls = readFileSync(env.TEST_LOG, 'utf8');
        for (const extra of [
            { TEST_ACTIVE: 'hhd@other.service loaded active running HHD' },
            { TEST_ENABLED: 'hhd@other.service enabled disabled' },
            { TEST_UID: '0' },
        ]) {
            const result = run(extra);
            assert.equal(result.status, 1);
            assert.doesNotMatch(result.stdout, /ready/);
        }
        const newCalls = readFileSync(env.TEST_LOG, 'utf8').slice(calls.length);
        assert.doesNotMatch(newCalls, /enable --now|read\n/);
        assert.equal(run({ TEST_ACTIVE: 'hhd@gamer.service loaded active running HHD' }).status, 0);
    } finally {
        rmSync(tmp, { recursive: true, force: true });
    }
});
