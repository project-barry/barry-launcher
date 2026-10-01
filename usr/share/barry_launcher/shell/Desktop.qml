// Barry Launcher in Desktop Mode: the AYN Thor's bottom screen as the top
// screen's trackpad and keyboard (TopInput.qml), started from the
// applications menu (barry_launcher_desktop). Full screen on the bottom
// panel, and never takes keyboard focus, so keys go to the window on top.
// Under KWin the pointer can cross onto the bottom screen too; the window
// under it gets the clicks.
import QtQuick
import QtQuick.Window

Window {
    id: win
    title: "Barry Launcher Trackpad"
    flags: Qt.WindowDoesNotAcceptFocus
    color: "black"

    readonly property real s: Math.min(width / 1240, height / 1080)

    // Portable version: barry_launcher_desktop passes the bottom panel's
    // connector, width and height after "--" (default: the Thor's).
    readonly property var panel: {
        const args = Qt.application.arguments
        const i = args.indexOf("--")
        const a = i >= 0 ? args.slice(i + 1) : []
        return { name: a[0] || "DSI-1", w: parseInt(a[1]) || 1240, h: parseInt(a[2]) || 1080 }
    }

    // The bottom panel: by connector, or else the screen shaped like it.
    function bottomScreen() {
        const all = Qt.application.screens
        for (let i = 0; i < all.length; i++)
            if (all[i].name === panel.name)
                return all[i]
        for (let i = 0; i < all.length; i++) {
            const w = all[i].width, h = all[i].height
            if ((w === panel.w && h === panel.h) || (w === panel.h && h === panel.w))
                return all[i]
        }
        return null
    }

    Component.onCompleted: {
        const bottom = bottomScreen()
        if (bottom) {
            win.screen = bottom
            win.x = bottom.virtualX
            win.y = bottom.virtualY
        } else {
            console.warn("no bottom screen found; opening on the current one")
        }
        win.showFullScreen()
    }

    TopInput {
        anchors.fill: parent
        s: win.s
        closeLabel: "✕ Close"
        onCloseRequested: Qt.quit()
    }
}
