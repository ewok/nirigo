// SPDX-License-Identifier: GPL-3.0-only
// nirigo replacement for sitolam/dms-plugins' focusable FloatingWindow.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common

PanelWindow {
    id: root

    required property var ydotool
    property bool keyboardVisible: false

    signal keyboardClosed
    signal unpinRequested

    function show() {
        keyboardVisible = true
        Qt.callLater(function() {
            movable.x = Math.max(0, (root.width - movable.width * movable.scale) / 2)
            movable.y = Math.max(0, root.height - movable.height * movable.scale - Theme.spacingL)
        })
    }

    function hide() {
        if (!keyboardVisible)
            return
        keyboardVisible = false
        keyboardClosed()
    }

    function constrainPosition() {
        if (!movable)
            return
        movable.x = Math.max(0, Math.min(movable.x, width - movable.width * movable.scale))
        movable.y = Math.max(0, Math.min(movable.y, height - movable.height * movable.scale))
    }

    visible: keyboardVisible
    color: "transparent"
    // The surface spans this screen; only the visible card accepts input.
    // Moving the card inside it avoids a focusable xdg-toplevel entirely.
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: 0
    WlrLayershell.namespace: "dms:plugins:virtualKeyboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        x: Math.floor(movable.x)
        y: Math.floor(movable.y)
        width: Math.ceil(movable.width * movable.scale)
        height: Math.ceil(movable.height * movable.scale)
    }

    onWidthChanged: constrainPosition()
    onHeightChanged: constrainPosition()

    Item {
        id: movable
        width: card.width
        height: handle.height + card.height
        // Fit the complete keyboard on small/rotated screens as well.
        scale: Math.min(1, root.width / width, root.height / height)
        transformOrigin: Item.TopLeft
        onScaleChanged: root.constrainPosition()
        x: Math.max(0, (root.width - width * scale) / 2)
        y: Math.max(0, root.height - height * scale - Theme.spacingL)

        Rectangle {
            id: handle
            width: parent.width
            height: Theme.spacingL * 2
            radius: Theme.cornerRadius
            color: Theme.readableSurface

            Rectangle {
                anchors.centerIn: parent
                width: Theme.spacingL * 3
                height: 4
                radius: 2
                color: Theme.surfaceText
            }

            // A dedicated handle avoids stealing touch presses from keys.
            DragHandler {
                target: movable
                xAxis.minimum: 0
                xAxis.maximum: Math.max(0, root.width - movable.width * movable.scale)
                yAxis.minimum: 0
                yAxis.maximum: Math.max(0, root.height - movable.height * movable.scale)
            }
        }

        KeyboardCard {
            id: card
            y: handle.height
            ydotool: root.ydotool
            pinned: true
            // No targetWindow: the upstream startSystemMove handle is disabled.
            onPinClicked: root.unpinRequested()
            onHideClicked: root.hide()
        }
    }
}
