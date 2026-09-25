import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "."

PluginComponent {
    id: root

    Component.onCompleted: TdpService.attach()
    Component.onDestruction: TdpService.detach()

    pillClickAction: () => TdpService.run(true)
    pillRightClickAction: () => TdpService.run(false)

    ccWidgetIcon: TdpService.icon
    ccWidgetPrimaryText: "Legion Go TDP"
    ccWidgetSecondaryText: TdpService.statusText
    ccWidgetIsToggle: false
    ccWidgetIsActive: !TdpService.error && TdpService.mode !== ""
    onCcWidgetToggled: TdpService.run(true)

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            opacity: TdpService.busy ? 0.6 : 1

            DankIcon {
                name: TdpService.icon
                size: root.iconSize
                color: TdpService.error ? Theme.error : Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: TdpService.statusText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            opacity: TdpService.busy ? 0.6 : 1

            DankIcon {
                name: TdpService.icon
                size: root.iconSize
                color: TdpService.error ? Theme.error : Theme.primary
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: TdpService.rotating && TdpService.busy ? "…" : TdpService.shortLabel
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
