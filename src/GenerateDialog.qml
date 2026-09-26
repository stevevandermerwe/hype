import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// "Generate with AI": a prompt goes to the configured endpoint and comes back as a new presentation folder.
Popup {
    id: dialog; objectName: "generateDialog"
    required property var ui
    required property real rounding
    signal generated(string path, var warnings)
    property string error: ""
    property bool showSettings: false
    // "plan": describe a talk. "mindmap": paste an outline to turn into slides.
    property string mode: "plan"
    readonly property bool mindMap: mode === "mindmap"
    function openAs(newMode) {
        if (mode !== newMode) promptField.clear()
        mode = newMode
        open()
    }
    parent: Overlay.overlay
    popupType: Popup.Item
    modal: true; focus: true; padding: 24
    closePolicy: ai.busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    width: Math.min(560, parent.width - 48)
    anchors.centerIn: parent
    Overlay.modal: Rectangle { color: "#660b0d14" }
    background: Rectangle { color: dialog.ui.panel; border.color: dialog.ui.border; radius: dialog.rounding }

    function start() {
        error = ""
        ai.saveSettings()
        ai.generate(promptField.text, themeBox.currentText, "", mode)
    }
    onOpened: { error = ""; promptField.forceActiveFocus() }
    Connections {
        target: ai
        function onSucceeded(path, warnings) { dialog.generated(path, warnings) }
        function onFailed(message) { dialog.error = message }
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
        implicitHeight: 38; implicitWidth: primary ? 120 : 84
        contentItem: Text { text: control.text; color: control.primary ? dialog.ui.accentText : dialog.ui.foreground; font.pixelSize: 14; font.bold: control.primary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle {
            color: !control.enabled ? dialog.ui.border : control.primary ? (control.hovered ? dialog.ui.accentHover : dialog.ui.accent) : (control.hovered ? dialog.ui.hover : dialog.ui.button)
            radius: Math.min(4, dialog.rounding)
        }
    }

    contentItem: ColumnLayout {
        spacing: 14
        Label { text: dialog.mindMap ? "Mind map" : "Generate with AI"; color: dialog.ui.foreground; font.pixelSize: 20; font.bold: true }
        Caption {
            text: dialog.mindMap ? "Paste your mind map: an indented outline, a Markdown list, or OPML exported from a mind-map tool. Each branch becomes slides, in your order and your words."
                                 : "Describe the presentation. Hype writes a new folder with the slides and their images, then opens it."
        }
        ScrollView {
            Layout.fillWidth: true; Layout.preferredHeight: dialog.mindMap ? 240 : 120
            enabled: !ai.busy
            TextArea {
                id: promptField; objectName: "generatePrompt"
                Accessible.name: dialog.mindMap ? "Mind map" : "Presentation prompt"
                wrapMode: TextEdit.Wrap; font.pixelSize: 14; color: dialog.ui.foreground
                selectionColor: dialog.ui.selection; selectedTextColor: dialog.ui.selectionText
                placeholderText: dialog.mindMap ? "Paste your mind map here…" : "A 10-slide talk on why small teams ship faster, for engineering managers…"
                placeholderTextColor: dialog.ui.muted
                background: Rectangle { color: dialog.ui.background; radius: Math.min(4, dialog.rounding); border.color: promptField.activeFocus ? dialog.ui.accent : dialog.ui.border }
                Keys.onPressed: function(event) {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) && promptField.text.trim()) {
                        dialog.start(); event.accepted = true
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Label { text: "Theme"; color: dialog.ui.muted; font.pixelSize: 13 }
            ComboBox {
                id: themeBox; Layout.fillWidth: true; enabled: !ai.busy
                model: deck.themeNames
                currentIndex: Math.max(0, deck.themeNames.indexOf(deck.themeName))
            }
        }
        Label {
            text: (dialog.showSettings ? "▾ " : "▸ ") + "Endpoint and model"
            color: dialog.ui.accent; font.pixelSize: 13
            Accessible.role: Accessible.Button; Accessible.name: "Endpoint and model settings"
            TapHandler { onTapped: dialog.showSettings = !dialog.showSettings }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
        ColumnLayout {
            visible: dialog.showSettings; Layout.fillWidth: true; spacing: 6
            Caption { text: "Endpoint (any OpenAI-compatible chat completions URL)" }
            Field { text: ai.endpoint; onEditingFinished: ai.endpoint = text; Accessible.name: "Endpoint" }
            Caption { text: "Model" }
            Field { text: ai.model; onEditingFinished: ai.model = text; Accessible.name: "Model" }
            Caption { text: "Environment variable holding the API key" }
            Field { text: ai.keyEnv; onEditingFinished: ai.keyEnv = text; Accessible.name: "API key variable" }
            Caption {
                text: ai.keySource ? "Using the key from " + ai.keySource + "." : "No API key found. Set that variable before launching Hype" + (ai.canStoreKey ? ", or save one to the Keychain below." : ".")
                color: ai.keySource ? dialog.ui.muted : dialog.ui.error
            }
            RowLayout {
                visible: ai.canStoreKey; Layout.fillWidth: true; spacing: 8
                Field { id: keyField; placeholderText: "Paste an API key to save it to the Keychain"; echoMode: TextInput.Password; Accessible.name: "API key" }
                DialogButton {
                    text: "Save key"; enabled: keyField.text.trim().length > 0 && !ai.busy
                    onClicked: { dialog.error = ai.storeKey(keyField.text); if (!dialog.error) keyField.clear() }
                }
            }
            Caption { text: "Prompt template file (leave empty for the built-in one; hype generate --print-template shows it)" }
            Field { text: ai.templatePath; onEditingFinished: ai.templatePath = text; Accessible.name: "Template file" }
            Caption { text: "New presentations are created in" }
            Field { text: ai.outputRoot; onEditingFinished: ai.outputRoot = text; Accessible.name: "Output folder" }
        }
        ColumnLayout {
            visible: ai.busy; Layout.fillWidth: true; spacing: 6
            ProgressBar { Layout.fillWidth: true; indeterminate: true; palette.highlight: dialog.ui.accent; palette.dark: dialog.ui.border; Accessible.name: "Generating" }
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
                objectName: "generateButton"; primary: true; text: "Generate"
                enabled: promptField.text.trim().length > 0 && !ai.busy
                onClicked: dialog.start()
            }
        }
    }
}
