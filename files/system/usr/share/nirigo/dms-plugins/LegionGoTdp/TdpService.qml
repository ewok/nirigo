pragma Singleton

import QtQuick
import Quickshell.Io
import qs.Services

QtObject {
    id: root

    // One backend for all bar placements and Control Center instances.
    property int consumers: 0
    property string mode: ""
    property string error: ""
    property bool busy: false
    property bool rotating: false
    readonly property var profiles: ({
        quiet: {label: "Quiet", shortLabel: "Q", icon: "eco"},
        balanced: {label: "Balanced", shortLabel: "B", icon: "balance"},
        performance: {label: "Performance", shortLabel: "P", icon: "speed"},
        custom: {label: "Custom", shortLabel: "C", icon: "tune"}
    })
    readonly property string label: error ? "Unavailable" : (profiles[mode]?.label ?? "Loading…")
    readonly property string shortLabel: error ? "!" : (profiles[mode]?.shortLabel ?? "…")
    readonly property string icon: error ? "error_outline" : (profiles[mode]?.icon ?? "speed")
    readonly property string statusText: rotating && busy ? "Switching…" : label

    function attach() {
        consumers += 1;
        if (consumers === 1)
            run(false);
    }

    function detach() {
        consumers = Math.max(0, consumers - 1);
    }

    function run(rotate) {
        if (busy || process.running)
            return;
        busy = true;
        rotating = rotate;
        const args = ["/usr/bin/timeout", "--kill-after=2s", "10s",
                      "/usr/bin/sudo", "-n", "/usr/libexec/rotatetdp.sh"];
        if (rotate)
            args.push("rotate");
        process.command = args;
        watchdog.restart();
        process.running = true;
    }

    function finish(exitCode, output, details) {
        if (!busy)
            return;
        watchdog.stop();
        const value = output.trim();
        const valid = ["quiet", "balanced", "performance", "custom"].includes(value);
        if (exitCode === 0 && valid) {
            mode = value;
            error = "";
            if (rotating)
                ToastService.showInfo("Legion Go TDP", profiles[value].label);
        } else {
            mode = "";
            error = details.trim() || "Could not read the HHD TDP profile (exit " + exitCode + ").";
            // Polling failures stay visible without generating repeated toasts.
            if (rotating)
                ToastService.showError("Legion Go TDP", error);
        }
        rotating = false;
        busy = false;
    }

    property Timer poll: Timer {
        interval: 5000
        repeat: true
        running: root.consumers > 0
        onTriggered: root.run(false)
    }

    // Also recover if the executable cannot start and no exited signal arrives.
    property Timer watchdog: Timer {
        interval: 15000
        onTriggered: {
            process.running = false;
            root.finish(-1, "", "TDP command timed out or could not start.");
        }
    }

    property Process process: Process {
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: (exitCode, exitStatus) => {
            root.finish(exitStatus === 0 ? exitCode : -1, output.text, errors.text);
        }
    }
}
