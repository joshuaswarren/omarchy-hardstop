import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Wind-down ritual overlay: four cards (stop, recap, tomorrow, close).
// Text state stays local and is handed to the service only at completion.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  property int cardIndex: 0
  property bool early: false
  property date now: new Date()

  readonly property string fontFamily: Style.font.menuFamily
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding

  readonly property int cardWidth: Math.min(Style.space(320), panel.width - Style.gapsOut * 2)
  readonly property int currentCardHeight: cardIndex === 0 ? stopCard.implicitHeight
    : cardIndex === 1 ? recapCard.implicitHeight
    : cardIndex === 2 ? tomorrowCard.implicitHeight
    : closeCard.implicitHeight
  readonly property int cardHeight: Math.min(
    contentMargin * 2 + progressDots.height + Style.spacing.xl + currentCardHeight,
    panel.height - Style.gapsOut * 2)

  readonly property string stopStatusLine: {
    if (root.early) return "Early wind-down"
    if (root.service && root.service.minutesOver > 0) return root.service.minutesOver + " min past stop"
    return ""
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    root.early = payload.early === true
    root.cardIndex = 0
    root.now = new Date()
    recapInput.text = ""
    tomorrowInput.text = ""
    root.opened = true
    Qt.callLater(function() { beginButton.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.joshuaswarren.hardstop")
  }

  function advance() {
    if (root.cardIndex < 3) root.cardIndex++
  }

  function finish() {
    if (root.service) root.service.completeRitual(recapInput.text, tomorrowInput.text)
    root.dismiss()
  }

  onCardIndexChanged: {
    Qt.callLater(function() {
      if (root.cardIndex === 0) beginButton.forceActiveFocus()
      else if (root.cardIndex === 1) recapInput.forceActiveFocus()
      else if (root.cardIndex === 2) tomorrowInput.forceActiveFocus()
      else doneButton.forceActiveFocus()
    })
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-hardstop"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: contentColumn
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.xl

        // Esc is handled once, here: unhandled keys bubble up from whichever
        // input holds focus, so every card dismisses without per-card copies.
        Keys.onEscapePressed: root.dismiss()

        Row {
          id: progressDots
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.sm

          Repeater {
            model: 4

            Rectangle {
              width: Style.spacing.sm
              height: Style.spacing.sm
              radius: width / 2
              color: index === root.cardIndex ? Color.accent : Color.muted

              Behavior on color { ColorAnimation { duration: 120 } }
            }
          }
        }

        Item {
          id: cardHolder
          width: parent.width
          height: root.currentCardHeight

          Behavior on height {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
          }

          Column {
            id: stopCard
            width: parent.width
            spacing: Style.spacing.lg

            property bool current: root.cardIndex === 0
            visible: current || opacity > 0
            opacity: current ? 1 : 0
            x: current ? 0 : Style.spacing.xxl

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "That's the day."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            Text {
              text: Qt.formatDateTime(root.now, "HH:mm")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            Text {
              visible: root.stopStatusLine !== ""
              text: root.stopStatusLine
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Row {
              spacing: Style.spacing.controlGap

              Button {
                id: beginButton
                text: "Begin wind-down"
                focusable: true
                onClicked: root.advance()
              }

              Button {
                text: "Not tonight"
                onClicked: root.dismiss()
              }
            }
          }

          Column {
            id: recapCard
            width: parent.width
            spacing: Style.spacing.lg

            property bool current: root.cardIndex === 1
            visible: current || opacity > 0
            opacity: current ? 1 : 0
            x: current ? 0 : Style.spacing.xxl

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Text {
              text: "How did today go?"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            BorderSurface {
              id: recapField
              width: parent.width
              height: recapRuler.height + Style.spacing.inputPaddingY * 2
                + contentTopInset + contentBottomInset
              radius: Style.cornerRadius
              color: Style.controlFill(recapInput.activeFocus, recapHot.hovered, root.foreground, Color.accent)
              borderSpec: Border.controlSpec(
                recapInput.activeFocus ? "focus" : (recapHot.hovered ? "hover-cursor" : "normal"),
                root.foreground, Color.accent)

              HoverHandler { id: recapHot }

              // Invisible five-line ruler: sizes the field to exactly five
              // lines of the input font without a magic line height.
              Text {
                id: recapRuler
                visible: false
                text: "\n\n\n\n"
                font: recapInput.font
              }

              TextEdit {
                id: recapInput
                anchors.fill: parent
                anchors.topMargin: recapField.contentTopInset + Style.spacing.inputPaddingY
                anchors.rightMargin: recapField.contentRightInset + Style.spacing.controlPaddingX
                anchors.bottomMargin: recapField.contentBottomInset + Style.spacing.inputPaddingY
                anchors.leftMargin: recapField.contentLeftInset + Style.spacing.controlPaddingX
                wrapMode: TextEdit.Wrap
                color: root.foreground
                selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                selectedTextColor: root.foreground
                selectByMouse: true
                font.family: root.fontFamily
                font.pixelSize: Style.font.body

                // Enter is a newline until the fifth line; Ctrl+Enter
                // finishes the card.
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                  if ((event.modifiers & Qt.ControlModifier)
                    && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                    root.advance()
                    event.accepted = true
                  } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    && recapInput.text.split("\n").length >= 5) {
                    event.accepted = true
                  }
                }

                // Paste can still land past the cap; clamp back to five lines.
                onTextChanged: {
                  var lines = text.split("\n")
                  if (lines.length > 5) {
                    var kept = lines.slice(0, 5).join("\n")
                    recapInput.text = kept
                    recapInput.cursorPosition = kept.length
                  }
                }
              }

              Text {
                visible: recapInput.length === 0 && !recapInput.activeFocus
                text: "One line per thought"
                color: Qt.darker(root.foreground, 1.6)
                font: recapInput.font
                anchors.fill: recapInput
                wrapMode: Text.WordWrap
              }
            }

            Button {
              text: "Continue"
              focusable: true
              onClicked: root.advance()
            }
          }

          Column {
            id: tomorrowCard
            width: parent.width
            spacing: Style.spacing.lg

            property bool current: root.cardIndex === 2
            visible: current || opacity > 0
            opacity: current ? 1 : 0
            x: current ? 0 : Style.spacing.xxl

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Text {
              text: "First action tomorrow"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            TextField {
              id: tomorrowInput
              width: parent.width
              foreground: root.foreground
              accent: Color.accent
              font.family: root.fontFamily
              placeholderText: "First thing you open at your desk"
              onAccepted: root.advance()
            }

            Button {
              text: "Continue"
              onClicked: root.advance()
            }
          }

          Column {
            id: closeCard
            width: parent.width
            spacing: Style.spacing.lg

            property bool current: root.cardIndex === 3
            visible: current || opacity > 0
            opacity: current ? 1 : 0
            x: current ? 0 : Style.spacing.xxl

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "See you tomorrow."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            // Ui/Button paints its focus fill over any custom background, so
            // the accent close button is its own surface: accent fill, menu
            // background text, focus shown by the control border spec.
            BorderSurface {
              id: doneButton
              width: parent.width
              height: doneLabel.implicitHeight + Style.spacing.panelGap * 2
              radius: Style.cornerRadius
              color: doneMouse.pressed ? Qt.darker(Color.accent, 1.15) : Color.accent
              borderSpec: Border.controlSpec(activeFocus ? "focus" : "normal", root.foreground, Color.accent)

              activeFocusOnTab: true
              Keys.onReturnPressed: root.finish()
              Keys.onEnterPressed: root.finish()

              Behavior on color { ColorAnimation { duration: 120 } }

              Text {
                id: doneLabel
                anchors.centerIn: parent
                text: "Done for today."
                color: Color.menu.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }

              MouseArea {
                id: doneMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.finish()
              }
            }
          }
        }
      }
    }
  }
}
