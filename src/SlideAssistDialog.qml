import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// "Ask AI" for one slide: rewrite its text, add a drawn diagram, or add a generated picture.
// The change is applied at once as a single edit, so Ctrl+Z undoes it.
Popup {
    id: dialog; objectName: "slideAssistDialog"
    required property var ui
    required property real rounding
    signal applied(string summary, var warnings)
    property string error: ""
    property string kind: "text" // "text", "diagram" or "image"
    property int slideIndex: -1
    readonly property var kinds: [
        { id: "text", label: "Text", hint: "Rewrites the slide's text.", example: "Make this punchier and cut it to three bullets" },
        { id: "diagram", label: "Diagram", hint: "Rewrites the text and draws an SVG picture beside it.", example: "Add a diagram of the request flow" },
        { id: "image", label: "Image", hint: "Adds a picture from the image model. The text stays as it is.", example: "A calm sunrise over a data center" }
    ]
    readonly property var current: kinds.find(function(k) { return k.id === kind })
    parent: Overlay.overlay
    popupType: Popup.Item
    modal: true; focus: true; padding: 24
    closePolicy: ai.busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    width: Math.min(520, parent.width - 48)
    anchors.centerIn: parent
    Overlay.modal: Rectangle { color: "#660b0d14" }
    background: Rectangle { color: dialog.ui.panel; border.color: dialog.ui.border; radius: dialog.rounding }

    function start() {
        error = ""
        slideIndex = deck.selected
        ai.saveSettings()
        ai.editSlide(request.text, kind, deck.slideText, deck.slideOutline(), slideIndex, deck.baseDirectory())
    }
    onOpened: { error = ""; request.forceActiveFocus() }
    Connections {
        target: ai
        function onSlideReady(slide, warnings, summary) {
            if (!dialog.visible) return
            if (deck.selected !== dialog.slideIndex) {
                dialog.error = "The selected slide changed while waiting, so nothing was applied."
                return
            }
            deck.editSlide(slide)
            request.clear()
            dialog.close()
            dialog.applied(summary, warnings)
        }
        function onFailed(message) { if (dialog.visible) dialog.error = message }
    }

    component Field: TextField {
        Layout.fillWidth: true; implicitHeight: 38
        font.pixelSize: 14; color: dialog.ui.foreground
        selectionColor: dialog.ui.selection; selectedTextColor: dialog.ui.selectionText
        placeholderTextColor: dialog.ui.muted
        leftPadding: 10; rightPadding: 10
        enabled: !ai.busy
        background: Rectangle { color: dialog.ui.background; radius: Math.min(4, dialog.rounding); border.color: parent.activeFocus ? dialog.ui.accent : dialog.ui.border }
    }
    component Caption: Label { color: dialog.ui.muted; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap }
    component DialogButton: Button {
        id: control
        property bool primary: false
        implicitHeight: 38; implicitWidth: primary ? 96 : 84
        contentItem: Text { text: control.text; color: control.primary ? dialog.ui.accentText : dialog.ui.foreground; font.pixelSize: 14; font.bold: control.primary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle {
            color: !control.enabled ? dialog.ui.border : control.primary ? (control.hovered ? dialog.ui.accentHover : dialog.ui.accent) : (control.hovered ? dialog.ui.hover : dialog.ui.button)
            radius: Math.min(4, dialog.rounding)
        }
    }

    contentItem: ColumnLayout {
        spacing: 14
        Label { text: "Ask AI"; color: dialog.ui.foreground; font.pixelSize: 20; font.bold: true }
        Caption { text: "Changes the selected slide. Undo with Ctrl+Z." }
        RowLayout {
            spacing: 8
            Repeater {
                model: dialog.kinds
                delegate: Button {
                    id: choice
                    required property var modelData
                    objectName: "assistKind-" + modelData.id
                    checkable: true; checked: dialog.kind === modelData.id
                    enabled: !ai.busy
                    implicitHeight: 34; implicitWidth: 92
                    onClicked: dialog.kind = modelData.id
                    contentItem: Text { text: choice.modelData.label; color: choice.checked ? dialog.ui.accentText : dialog.ui.foreground; font.pixelSize: 14; font.bold: choice.checked; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle {
                        color: choice.checked ? dialog.ui.accent : choice.hovered ? dialog.ui.hover : dialog.ui.button
                        radius: Math.min(4, dialog.rounding)
                    }
                }
            }
        }
        Caption { text: dialog.current.hint }
        ScrollView {
            Layout.fillWidth: true; Layout.preferredHeight: 88
            enabled: !ai.busy
            TextArea {
                id: request; objectName: "assistRequest"
                Accessible.name: "What to change"
                wrapMode: TextEdit.Wrap; font.pixelSize: 14; color: dialog.ui.foreground
                selectionColor: dialog.ui.selection; selectedTextColor: dialog.ui.selectionText
                placeholderText: dialog.current.example + "…"
                placeholderTextColor: dialog.ui.muted
                background: Rectangle { color: dialog.ui.background; radius: Math.min(4, dialog.rounding); border.color: request.activeFocus ? dialog.ui.accent : dialog.ui.border }
                Keys.onPressed: function(event) {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier) && request.text.trim()) {
                        dialog.start(); event.accepted = true
                    }
                }
            }
        }
        ColumnLayout {
            visible: dialog.kind === "image"; Layout.fillWidth: true; spacing: 6
            Caption { text: "Image model (uses the same API key)" }
            Field { text: ai.imageModel; onEditingFinished: ai.imageModel = text; Accessible.name: "Image model" }
            Caption { text: "Image endpoint (leave empty to use the chat endpoint)" }
            Field { text: ai.imageEndpoint; placeholderText: ai.endpoint; onEditingFinished: ai.imageEndpoint = text; Accessible.name: "Image endpoint" }
        }
        Caption {
            visible: dialog.kind !== "text" && deck.baseDirectory() === ""
            text: "Save the presentation first (Ctrl+S), so the picture has a folder to go in."
            color: dialog.ui.error
        }
        Caption {
            visible: !ai.keySource
            text: "No API key found. Set it up under File → Generate with AI… → Endpoint and model."
            color: dialog.ui.error
        }
        ColumnLayout {
            visible: ai.busy; Layout.fillWidth: true; spacing: 6
            ProgressBar { Layout.fillWidth: true; indeterminate: true; palette.highlight: dialog.ui.accent; palette.dark: dialog.ui.border; Accessible.name: "Working" }
            Caption { text: ai.status; color: dialog.ui.foreground }
        }
        Label {
            Layout.fillWidth: true; visible: dialog.error.length > 0 && !ai.busy
            text: dialog.error; color: dialog.ui.error; font.pixelSize: 13; wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Item { Layout.fillWidth: true }
            DialogButton { text: ai.busy ? "Stop" : "Close"; onClicked: ai.busy ? ai.cancel() : dialog.close() }
            DialogButton {
                objectName: "assistGo"; primary: true; text: "Go"
                enabled: request.text.trim().length > 0 && !ai.busy
                onClicked: dialog.start()
            }
        }
    }
}
