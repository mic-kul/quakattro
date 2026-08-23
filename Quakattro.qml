import Quickshell
import Quickshell.Wayland
import QtQuick

// Omarchy plugin entry point, overlay kind.
//
// Plugins share the long-running Omarchy shell process, so two rules govern
// everything here: never quit the process, and never render while closed.
Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false

    function open(payloadJson) {
        root.opened = true;
        Qt.callLater(function () { game.forceActiveFocus(); });
    }

    function close() {
        root.opened = false;
    }

    // Hand the surface back to the shell, rather than tearing anything down.
    function dismiss() {
        root.opened = false;
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide((root.manifest && root.manifest.id) || "quakattro");
    }

    function toggle() {
        if (root.opened) root.dismiss();
        else root.open("{}");
    }

    PanelWindow {
        id: panel
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "quakattro"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        Game {
            id: game
            anchors.fill: parent
            active: root.opened
            // Esc inside the game asks to leave; the plugin decides what that
            // means, and it never means Qt.quit().
            onExitRequested: root.dismiss()
        }
    }
}
