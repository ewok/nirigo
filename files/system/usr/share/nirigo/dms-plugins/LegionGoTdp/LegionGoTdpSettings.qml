import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "legionGoTdp"

    StyledText {
        width: parent.width
        text: "Click the DankBar pill or press Mod+Ctrl+T to advance the SteamOS Manager TDP limit by one watt. The value wraps from the hardware maximum to its minimum."
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
