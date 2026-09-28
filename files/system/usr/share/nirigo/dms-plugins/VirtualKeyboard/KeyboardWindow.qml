// SPDX-License-Identifier: GPL-3.0-only
// Based on sitolam/dms-plugins; nirigo modification: never take keyboard focus.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

PanelWindow {
    id: root

    required property var ydotool
    property bool keyboardVisible: false

    signal keyboardClosed
    signal pinRequested

    function show() {
        keyboardVisible = true
    }

    function hide() {
        if (!keyboardVisible)
            return
        keyboardVisible = false
        keyboardClosed()
    }

    visible: keyboardVisible
    color: "transparent"

    anchors {
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    implicitWidth: card.width
    implicitHeight: card.height + Theme.spacingL * 2

    WlrLayershell.namespace: "dms:plugins:virtualKeyboard"
    WlrLayershell.layer: WlrLayer.Overlay
    // Touch/pointer events still reach the keys, but ydotool input goes to
    // the application that was focused before the keyboard was touched.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        item: card
    }

    WindowBlur {
        targetWindow: root
        blurX: card.x
        blurY: card.y
        blurWidth: root.keyboardVisible ? card.width : 0
        blurHeight: root.keyboardVisible ? card.height : 0
        blurRadius: Theme.cornerRadius
    }

    KeyboardCard {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacingL
        ydotool: root.ydotool
        pinned: false
        onPinClicked: root.pinRequested()
        onHideClicked: root.hide()
    }
}
