import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    property string gpuMode: "GPU: unknown"

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Process {
        id: gpuStatus
        command: ["sh", "-lc", "state=$(cat /run/gpu-passthrough-switch.state 2>/dev/null || true); printf '%s' \"${state:-not installed}\""]
        stdout: StdioCollector {
            onStreamFinished: root.gpuMode = "GPU: " + this.text.trim()
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: if (!gpuStatus.running) gpuStatus.running = true
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            anchors.top: true
            anchors.left: true
            anchors.right: true
            implicitHeight: 38
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: "#e609090d"
                border.color: "#805c2f85"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 14

                    Text {
                        text: "RM / HYPR"
                        color: "#b78bd8"
                        font.family: "JetBrains Mono"
                        font.bold: true
                    }

                    Text {
                        text: "Alt+Space apps  ·  Ctrl+Shift+Space keys"
                        color: "#a7a4ae"
                        font.family: "JetBrains Mono"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        implicitWidth: gpuText.implicitWidth + 18
                        implicitHeight: 26
                        radius: 7
                        color: root.gpuMode.indexOf("vm") >= 0 ? "#5c2f85" : "#23212a"

                        Text {
                            id: gpuText
                            anchors.centerIn: parent
                            text: root.gpuMode
                            color: "#f1eff5"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 12
                        }
                    }

                    Text {
                        text: Qt.formatDateTime(clock.date, "ddd dd MMM  HH:mm")
                        color: "#f1eff5"
                        font.family: "JetBrains Mono"
                        font.bold: true
                    }
                }
            }
        }
    }
}
