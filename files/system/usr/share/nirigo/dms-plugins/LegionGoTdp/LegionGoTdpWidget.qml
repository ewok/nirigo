import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string watts: "--"
    property string profile: "--"
    property string lastError: ""

    function run(command, output) {
        if (!tdp.running) {
            tdp.command = command
            tdp.output = output
            tdp.running = true
        }
    }

    function refresh() {
        run(["/usr/libexec/nirigo-tdp", "profile"], "profile")
    }

    function selectProfile(name) {
        run(["/usr/libexec/nirigo-tdp", "profile", name], "profile")
    }

    function rotate() {
        run(["/usr/libexec/nirigo-tdp", "rotate"], "tdp")
    }

    Component.onCompleted: refresh()

    Process {
        id: tdp
        property string output: ""
        stdout: SplitParser {
            onRead: data => {
                const value = data.trim()
                if (tdp.output === "profile") {
                    root.profile = value
                    if (value === "custom")
                        root.run(["/usr/libexec/nirigo-tdp"], "tdp")
                } else if (/^[0-9]+$/.test(value)) {
                    root.watts = value
                    root.lastError = ""
                }
            }
        }
        stderr: SplitParser {
            onRead: data => root.lastError = data.trim()
        }
    }

    pillClickAction: () => root.selectProfile(root.profile === "low-power" ? "balanced" : root.profile === "balanced" ? "performance" : root.profile === "performance" ? "custom" : "low-power")

    horizontalBarPill: Component {
        StyledRect {
            width: Math.max(parent.widgetThickness * 1.6, label.implicitWidth + 16)
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            StyledText {
                id: label
                anchors.centerIn: parent
                text: root.profile === "custom" ? root.watts + " W" : root.profile
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: Math.max(parent.widgetThickness * 1.6, label.implicitHeight + 16)
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            StyledText {
                id: label
                anchors.centerIn: parent
                text: root.profile === "custom" ? root.watts + "W" : root.profile
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                rotation: -90
            }
        }
    }
}
