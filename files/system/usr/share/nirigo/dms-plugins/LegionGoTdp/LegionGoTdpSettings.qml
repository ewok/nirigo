import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "legionGoTdp"

    StyledText {
        width: parent.width
        text: "Click the DankBar pill to cycle low-power, balanced, performance, and custom profiles. Custom displays its TDP limit. Mod+Ctrl+T selects custom, then advances TDP by one watt; the value wraps at the hardware maximum."
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
