pragma Singleton

import QtQuick
import Quickshell.Io
import qs.Services

QtObject {
    id: root

    property int consumers: 0
    property string mode: ""
    property string error: ""
    property bool busy: false
    property bool rotating: false
    readonly property var profiles: ({
        "low-power": {label: "Low Power", shortLabel: "L", icon: "eco"},
        balanced: {label: "Balanced", shortLabel: "B", icon: "balance"},
        performance: {label: "Performance", shortLabel: "P", icon: "speed"},
        custom: {label: "Custom", shortLabel: "C", icon: "tune"}
    })
    readonly property string label: error ? "Unavailable" : (profiles[mode]?.label ?? "Loading...")
    readonly property string shortLabel: error ? "!" : (profiles[mode]?.shortLabel ?? "...")
    readonly property string icon: error ? "error_outline" : (profiles[mode]?.icon ?? "speed")
    readonly property string statusText: rotating && busy ? "Switching..." : label

    function attach() {
        consumers += 1
        if (consumers === 1)
            run(false)
    }

    function detach() {
        consumers = Math.max(0, consumers - 1)
    }

    function run(rotate) {
        if (busy || process.running)
            return
        busy = true
        rotating = rotate
        process.command = ["/usr/libexec/nirigo-tdp", "profile"]
        if (rotate)
            process.command.push(nextProfile())
        process.running = true
    }

    function nextProfile() {
        if (mode === "low-power")
            return "balanced"
        if (mode === "balanced")
            return "performance"
        if (mode === "performance")
            return "custom"
        return "low-power"
    }

    function finish(exitCode, output, details) {
        const value = output.trim()
        if (exitCode === 0 && profiles[value]) {
            mode = value
            error = ""
            if (rotating)
                ToastService.showInfo("Legion Go TDP", profiles[value].label)
        } else {
            mode = ""
            error = details.trim() || "Could not read the Legion Go performance profile."
            if (rotating)
                ToastService.showError("Legion Go TDP", error)
        }
        rotating = false
        busy = false
    }

    property Timer poll: Timer {
        interval: 5000
        repeat: true
        running: root.consumers > 0
        onTriggered: root.run(false)
    }

    property Process process: Process {
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: exitCode => root.finish(exitCode, output.text, errors.text)
    }
}
