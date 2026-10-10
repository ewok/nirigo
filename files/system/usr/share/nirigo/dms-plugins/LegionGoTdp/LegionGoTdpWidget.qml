import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string watts: "--"
    property string lastError: ""

    function refresh() {
        if (!tdp.running) {
            tdp.command = ["/usr/libexec/nirigo-tdp"]
            tdp.running = true
        }
    }

    function rotate() {
        if (!tdp.running) {
            tdp.command = ["/usr/libexec/nirigo-tdp", "rotate"]
            tdp.running = true
        }
    }

    Component.onCompleted: refresh()

    Process {
        id: tdp
        stdout: SplitParser {
            onRead: data => {
                const value = data.trim()
                if (/^[0-9]+$/.test(value)) {
                    root.watts = value
                    root.lastError = ""
                }
            }
        }
        stderr: SplitParser {
            onRead: data => root.lastError = data.trim()
        }
    }

    pillClickAction: rotate

    horizontalBarPill: Component {
        StyledRect {
            width: Math.max(parent.widgetThickness * 1.6, label.implicitWidth + 16)
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            StyledText {
                id: label
                anchors.centerIn: parent
                text: root.watts + " W"
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
                text: root.watts + "W"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                rotation: -90
            }
        }
    }
}
