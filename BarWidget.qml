import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Countdown-to-quitting-time chip. Presentation only: every state comes from
// the hardstop service, so the chip renders nothing until that service is up.
//
// Escalation is monotonic (from the design review): idle is dimmed, warning
// carries the accent, final is an accent pill with bold minutes, and past
// stop keeps the pill in urgent with the overage count, so the most
// important moment is never quieter than the one before it.
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
  readonly property bool finalPill: phase === "final" || over
  readonly property bool dimmedIdle: (phase === "offday" || phase === "done")
    && (service ? service.showWhenIdle === true : false)
  readonly property bool chipVisible: service !== null && (countsDown || over || dimmedIdle)

  // nf-weather block (stable in the installed bar font; the newer md-*
  // block is version-shifted there). Sunset counts down, the sun sets past
  // stop, no-schedule days get a set moon, a finished day a full one.
  readonly property string glyph: phase === "offday" ? "\ue3c2"
    : phase === "done" ? "\ue39b"
    : "\ue34d"

  readonly property string timeText: countsDown && service
    ? String(service.remainingText ?? "")
    : over ? root.minutesOver + " min" : ""

  // Idle rests at the shell's own dimming lever (WidgetButton.dimmed) so the
  // first value step of the ladder is quiet, not mid-gray.
  readonly property color contentColor: over ? Color.bar.background
    : phase === "final" ? Color.bar.background
    : phase === "warning" ? Color.accent
    : button.foreground

  readonly property var verticalStack: {
    var stack = [root.glyph]
    if (root.finalPill) {
      stack.push(String(root.minutesRemaining), "min")
    } else if (root.countsDown) {
      var parts = root.timeText.split(":")
      if (parts.length >= 2) stack.push(parts[0], parts[1])
      else if (parts[0] !== "") stack.push(parts[0])
    } else if (root.over) {
      stack.push(String(root.minutesOver), "min")
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

  // One soft breath per minute in warning: a slight swell, never a dim
  // (escalation must not get quieter), never looping.
  SequentialAnimation {
    id: warningPulse
    NumberAnimation { target: chipContent; property: "scale"; to: 1.07; duration: 300; easing.type: Easing.OutCubic }
    NumberAnimation { target: chipContent; property: "scale"; to: 1; duration: 360; easing.type: Easing.OutCubic }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.chipVisible
    dimmed: root.dimmedIdle || root.phase === "idle"
    horizontalMargin: Style.spaceReal(8.75)
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

      // Final/past-stop pill: declared before the row so the label paints
      // on top. Caps need more horizontal room than vertical padding buys.
      Rectangle {
        visible: root.finalPill && !root.vertical
        anchors.centerIn: chipRow
        width: chipRow.implicitWidth + Style.spacing.xl * 2
        height: chipRow.implicitHeight + Style.spacing.sm * 2
        radius: height / 2
        color: root.over ? Color.urgent : Color.notifications.countdown
      }

      Row {
        id: chipRow
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: Style.spacing.sm

        OpticalGlyph {
          width: Style.bar.iconSlot
          height: Style.bar.iconSlot
          text: root.glyph
          fontFamily: button.fontFamily
          fontSize: button.fontSize
          color: root.contentColor
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
      spacing: Style.spacing.rowGap

      Button {
        width: parent.width
        leftAlign: true
        text: "Snooze 15 min (" + root.snoozesLeft + " left)"
        enabled: root.canSnooze
        opacity: enabled ? 1 : 0.45
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

      // Help leaves the app; separate it from the day actions.
      PanelSeparator {}

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
