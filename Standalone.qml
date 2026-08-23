import QtQuick
import QtQuick.Window

// Development runner: qml6 Standalone.qml
// An ordinary window, so a hung frame costs you a window and nothing else.
Window {
    width: 1000
    height: 640
    visible: true
    color: "black"
    title: "Quakattro"

    Game {
        anchors.fill: parent
        active: true
        onExitRequested: Qt.quit()
    }
}
