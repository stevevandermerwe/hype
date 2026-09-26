import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The start page: four ways to begin, and the presentations you were last working on.
Item {
    id: page; objectName: "startPage"
    required property var ui
    required property real rounding
    property var recent: []
    signal openRequested()
    signal wingRequested()
    signal planRequested()
    signal mindMapRequested()
    signal recentChosen(string path)
    signal dismissed()

    readonly property var choices: [
        { key: "O", title: "Open", blurb: "Continue with a presentation you already have", icon: "open", action: "open" },
        { key: "W", title: "Wing it", blurb: "Start with a blank slide and just write", icon: "visual", action: "wing" },
        { key: "P", title: "Plan it", blurb: "Describe your talk and let AI draft it", icon: "overview", action: "plan" },
        { key: "M", title: "Mind map", blurb: "Paste an outline and turn it into slides", icon: "mindmap", action: "mindmap" }
    ]
    function choose(action) {
        if (action === "open") openRequested()
        else if (action === "wing") wingRequested()
        else if (action === "plan") planRequested()
        else if (action === "mindmap") mindMapRequested()
    }
    function refresh() { recent = deck.recentPresentations(); forceActiveFocus() }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: if (visible) refresh()
    focus: visible
    Keys.onPressed: function(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier)) return
        if (event.key === Qt.Key_Escape) { dismissed(); event.accepted = true; return }
        for (const choice of choices)
            if (event.text.toUpperCase() === choice.key) { choose(choice.action); event.accepted = true; return }
    }

    Rectangle { anchors.fill: parent; color: page.ui.background }
    MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: function(wheel) { wheel.accepted = true } }

    Flickable {
        anchors.fill: parent
        contentHeight: Math.max(height, content.implicitHeight + 96)
        clip: true
        ScrollBar.vertical: ScrollBar {}
        ColumnLayout {
            id: content
            width: Math.min(parent.width - 96, 940)
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(48, (parent.height - implicitHeight) / 2)
            spacing: 32

            ColumnLayout {
                spacing: 6
                Label { text: "Hype"; color: page.ui.accent; font.pixelSize: 56; font.bold: true }
                Label { text: "How do you want to start?"; color: page.ui.muted; font.pixelSize: 20 }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: page.width >= 1000 ? 4 : 2
                columnSpacing: 16; rowSpacing: 16
                Repeater {
                    model: page.choices
                    delegate: Button {
                        id: card
                        required property var modelData
                        objectName: "startCard-" + modelData.action
                        Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.preferredHeight: 180
                        Accessible.name: modelData.title + ". " + modelData.blurb
                        onClicked: page.choose(modelData.action)
                        contentItem: ColumnLayout {
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                AppIcon { name: card.modelData.icon; width: 30; height: 30; implicitWidth: 30; implicitHeight: 30; color: page.ui.accent }
                                Item { Layout.fillWidth: true }
                                Label {
                                    text: card.modelData.key; color: page.ui.muted; font.pixelSize: 12
                                    leftPadding: 7; rightPadding: 7; topPadding: 2; bottomPadding: 2
                                    background: Rectangle { color: "transparent"; border.color: page.ui.border; radius: 4 }
                                }
                            }
                            Item { Layout.fillHeight: true }
                            Label { text: card.modelData.title; color: page.ui.foreground; font.pixelSize: 24; font.bold: true }
                            Label { text: card.modelData.blurb; color: page.ui.muted; font.pixelSize: 14; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                        background: Rectangle {
                            color: card.hovered || card.down ? page.ui.hover : page.ui.panel
                            radius: page.rounding
                            border.width: card.hovered || card.activeFocus ? 2 : 1
                            border.color: card.hovered || card.activeFocus ? page.ui.accent : page.ui.border
                        }
                    }
                }
            }

            ColumnLayout {
                visible: page.recent.length > 0
                Layout.fillWidth: true; spacing: 4
                Label { text: "Recent"; color: page.ui.muted; font.pixelSize: 14; font.bold: true; Layout.bottomMargin: 4 }
                Repeater {
                    model: page.recent.slice(0, 5)
                    delegate: ItemDelegate {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: 48
                        Accessible.name: "Open " + modelData.name
                        onClicked: page.recentChosen(modelData.path)
                        contentItem: RowLayout {
                            spacing: 12
                            Label { text: row.modelData.name; color: page.ui.foreground; font.pixelSize: 16; elide: Text.ElideRight; Layout.maximumWidth: parent.width * 0.5 }
                            Label { text: row.modelData.folder; color: page.ui.muted; font.pixelSize: 13; elide: Text.ElideMiddle; Layout.fillWidth: true }
                        }
                        background: Rectangle { color: row.hovered || row.activeFocus ? page.ui.hover : "transparent"; radius: Math.min(4, page.rounding) }
                    }
                }
            }

            Label {
                text: "Back to editing (Esc)"; color: page.ui.muted; font.pixelSize: 13
                Accessible.role: Accessible.Button; Accessible.name: "Back to editing"
                TapHandler { onTapped: page.dismissed() }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }
    }
}
