import QtQuick
import Quickshell.Io
import Quickshell
import qs.Commons
import qs.Ui

// Countdown-to-quitting-time chip. Presentation only: every state comes from
// the hardstop service, so the chip renders nothing until that service is up.
BarWidget {
  id: root
  moduleName: "io.github.joshuaswarren.hardstop"

  readonly property var service: bar?.shell?.serviceFor("io.github.joshuaswarren.hardstop") ?? null

  readonly property string phase: service ? String(service.phase ?? "") : ""
  readonly property int minutesRemaining: service ? Number(service.minutesRemaining ?? 0) : 0
  readonly property int minutesOver: service ? Number(service.minutesOver ?? 0) : 0
  readonly property bool canSnooze: service ? service.canSnooze === true : false
  readonly property int snoozesLeft: service
    ? Math.max(0, Number(service.maxSnoozes ?? 0) - Number(service.snoozeCount ?? 0))
    : 0

  readonly property bool countsDown: phase === "idle" || phase === "warning" || phase === "final"
  readonly property bool over: phase === "over"
  readonly property bool finalPill: phase === "final"
  readonly property bool dimmedIdle: (phase === "offday" || phase === "done")
    && (service ? service.showWhenIdle === true : false)
  readonly property bool chipVisible: service !== null && (countsDown || over || dimmedIdle)

  // nf-weather-sunset (U+E34D), from the same weather-icons block the
  // first-party weather widget paints, so the codepoint is stable in the
  // installed bar font (the newer md-* block is version-shifted there).
  readonly property string glyph: ""

  readonly property string timeText: countsDown && service ? String(service.remainingText ?? "") : ""

  // Muted bar text darkens the bar foreground (media-widget idiom) rather
  // than using palette `muted`, so a per-bar foreground theme still holds.
  readonly property color contentColor: finalPill ? Color.bar.background
    : phase === "warning" ? Color.accent
    : over ? Color.urgent
    : Qt.darker(button.foreground, 1.5)

  readonly property var verticalStack: {
    var stack = [root.glyph]
    if (root.finalPill) {
      stack.push(String(root.minutesRemaining), "min")
    } else if (root.countsDown) {
      var parts = root.timeText.split(":")
      if (parts.length >= 2) stack.push(parts[0], parts[1])
      else if (parts[0] !== "") stack.push(parts[0])
    }
    return stack
  }

  property bool menuOpen: false

  function close() { menuOpen = false }

  // The chip's context menu, addressable for keybindings and scripts.
  IpcHandler {
    target: "hardstop.chip"

    function menu(): void { root.menuOpen = true }
    function hideMenu(): void { root.close() }
  }

  visible: chipVisible
  implicitWidth: chipVisible ? button.implicitWidth : 0
  implicitHeight: chipVisible ? button.implicitHeight : 0

  onMinutesRemainingChanged: {
    if (phase === "warning" && chipVisible) warningPulse.restart()
  }

  // One soft pulse per minute in warning — triggered on the minute change,
  // never looping, so an unattended bar animates nothing.
  SequentialAnimation {
    id: warningPulse
    NumberAnimation { target: chipContent; property: "opacity"; to: 0.55; duration: 300; easing.type: Easing.OutCubic }
    NumberAnimation { target: chipContent; property: "opacity"; to: 1; duration: 360; easing.type: Easing.OutCubic }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.chipVisible
    dimmed: root.dimmedIdle
    horizontalMargin: 8.75
    fixedWidth: root.vertical ? -1 : chipRow.implicitWidth + button.scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? root.verticalStack.length * Style.bar.iconSlot : -1
    tooltipText: root.over && root.minutesOver > 0 ? root.minutesOver + " min past stop" : ""

    onPressed: function(b) {
      if (!root.service) return
      if (b === Qt.MiddleButton) {
        if (root.canSnooze) root.service.snooze()
      } else if (b === Qt.RightButton) {
        root.menuOpen = !root.menuOpen
      } else {
        root.service.openWindDown(true)
      }
    }

    Item {
      id: chipContent
      anchors.fill: parent

      // Final-state pill: declared before the row so the label paints on top.
      Rectangle {
        visible: root.finalPill && !root.vertical
        anchors.centerIn: chipRow
        width: chipRow.implicitWidth + Style.spacing.lg * 2
        height: chipRow.implicitHeight + Style.spacing.xs * 2
        radius: height / 2
        color: Color.accent
      }

      Row {
        id: chipRow
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: Style.spacing.sm

        Text {
          text: root.glyph
          color: root.contentColor
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          visible: root.timeText !== ""
          text: root.timeText
          color: root.contentColor
          font.bold: root.finalPill
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Column {
        visible: root.vertical
        anchors.fill: parent

        Repeater {
          model: root.verticalStack

          OpticalGlyph {
            required property string modelData
            width: button.width
            height: Style.bar.iconSlot
            text: modelData
            fontFamily: button.fontFamily
            fontSize: modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize
            color: root.contentColor
          }
        }
      }
    }
  }

  PopupCard {
    id: menu
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.menuOpen
    contentWidth: menu.fittedContentWidth(Style.space(230))
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    Column {
      id: menuColumn
      anchors.fill: parent
      spacing: Style.spacing.xs

      Button {
        width: parent.width
        leftAlign: true
        text: "Snooze 15 min (" + root.snoozesLeft + " left)"
        enabled: root.canSnooze
        opacity: enabled ? 1 : 0.4
        onClicked: {
          if (root.service) root.service.snooze()
          root.close()
        }
      }

      Button {
        width: parent.width
        leftAlign: true
        text: "Skip today"
        onClicked: {
          if (root.service) root.service.skipToday()
          root.close()
        }
      }

      Button {
        width: parent.width
        leftAlign: true
        text: "Help"
        onClicked: {
          Quickshell.execDetached(["xdg-open", "https://github.com/joshuaswarren/omarchy-hardstop"])
          root.close()
        }
      }
    }
  }
}
