import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "i18n/I18n.js" as I18n

Panel {
  id: root
  moduleName: "io.github.etroll.omarchy-airplay"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var homepodOutputs: []
  property int homepodActiveCount: 0
  property var receivers: []
  property string selectedName: ""
  property string selectedAddress: ""
  property string selectedDeviceId: ""
  property bool pairingRequired: false
  property bool pairingPromptActive: false
  property string discoveryError: ""
  property string streamError: ""
  property bool mirroring: false
  property string networkDescription: ""
  property string firewallError: ""
  property bool firewallManaged: false

  // Main navigation tabs: "screens" | "miracast" | "audio"
  property string mainTab: "screens"
  // Screens sub-filter: "all" | "airplay" | "cast"
  property string screenFilter: "all"

  readonly property var screenReceivers: {
    var list = root.receivers.filter(function(r) { return (r.protocol || "airplay") !== "wfd" })
    if (root.screenFilter === "all") return list
    return list.filter(function(r) { return (r.protocol || "airplay") === root.screenFilter })
  }

  readonly property var miracastReceivers: root.receivers.filter(function(r) { return r.protocol === "wfd" })

  readonly property int airplayCount: root.receivers.filter(function(r) { return (r.protocol || "airplay") === "airplay" }).length
  readonly property int wfdCount: root.receivers.filter(function(r) { return r.protocol === "wfd" }).length
  readonly property int castCount: root.receivers.filter(function(r) { return r.protocol === "cast" }).length

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string localeName: Qt.locale().name

  function t(key, values) { return I18n.t(root.localeName, key, values) }

  function open() {
    root.controller.show()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.spacing.panelGap

        PanelHero {
          title: root.t("airplayMirror")
          meta: root.mirroring
            ? root.t("mirroringTo", { name: root.selectedName })
            : (root.selectedAddress !== "" ? root.t("readyFor", { name: root.selectedName }) : root.t("chooseReceiver"))
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              text: root.mainTab === "audio" ? "󰓃" : (root.mainTab === "miracast" ? "󰖟" : "󰐨")
              color: root.mirroring || root.homepodActiveCount > 0 ? Color.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          trailingControl: Component {
            PanelActionButton {
              iconText: "󰑐"
              tooltipText: root.t("discoverReceivers")
              foreground: root.foreground
              hoverColor: Color.accent
              fontFamily: root.fontFamily
              onClicked: if (root.hostWidget) root.hostWidget.discover()
            }
          }
        }

        Text {
          visible: root.streamError !== ""
          width: parent.width
          text: root.streamError
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ==========================================
        // MAIN NAVIGATION TABS (Displays / Miracast / Audio)
        // ==========================================
        Row {
          width: parent.width
          spacing: Style.spacing.xs

          Repeater {
            model: [
              { id: "screens", label: "Displays", icon: "󰐨", count: root.screenReceivers.length },
              { id: "miracast", label: "Miracast", icon: "󰖟", count: root.wfdCount },
              { id: "audio", label: "Audio", icon: "󰓃", count: root.homepodOutputs.length }
            ]

            delegate: Rectangle {
              id: mainTabBtn
              required property var modelData
              readonly property bool isCurrent: root.mainTab === modelData.id
              width: (contentColumn.width - Style.spacing.xs * 2) / 3
              height: Style.space(32)
              radius: Style.cornerRadius
              color: isCurrent ? Color.accent : (tabMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent")
              border.width: isCurrent ? 0 : 1
              border.color: isCurrent ? "transparent" : root.dim

              Row {
                anchors.centerIn: parent
                spacing: Style.spacing.xs

                Text {
                  text: mainTabBtn.modelData.icon
                  color: mainTabBtn.isCurrent ? "#ffffff" : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: mainTabBtn.modelData.label + (mainTabBtn.modelData.count > 0 ? (" (" + mainTabBtn.modelData.count + ")") : "")
                  color: mainTabBtn.isCurrent ? "#ffffff" : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: mainTabBtn.isCurrent
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                id: tabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.mainTab = mainTabBtn.modelData.id
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ==========================================
        // TAB 1: SCREENS & DISPLAYS VIEW
        // ==========================================
        Column {
          visible: root.mainTab === "screens"
          width: parent.width
          spacing: Style.spacing.panelGap

          // Protocol sub-filters
          Row {
            width: parent.width
            spacing: Style.spacing.xs

            Repeater {
              model: [
                { id: "all", label: "All Displays (" + (root.airplayCount + root.castCount) + ")" },
                { id: "airplay", label: "AirPlay 2 (" + root.airplayCount + ")" },
                { id: "cast", label: "Google Cast (" + root.castCount + ")" }
              ]

              delegate: Rectangle {
                id: subPill
                required property var modelData
                readonly property bool active: root.screenFilter === modelData.id
                width: (contentColumn.width - Style.spacing.xs * 2) / 3
                height: Style.space(24)
                radius: Style.cornerRadius
                color: active ? Style.hoverFillFor(Color.accent, root.foreground) : "transparent"
                border.width: 1
                border.color: active ? Color.accent : root.dim

                Text {
                  anchors.centerIn: parent
                  text: subPill.modelData.label
                  color: subPill.active ? Color.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  font.bold: subPill.active
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.screenFilter = subPill.modelData.id
                }
              }
            }
          }

          Text {
            visible: root.screenReceivers.length === 0
            width: parent.width
            text: root.discoveryError !== "" ? root.discoveryError : root.t("noReceivers")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // Smooth ListView for Screen Receivers
          ListView {
            id: screenListView
            width: parent.width
            height: Math.min(contentHeight, Style.space(380))
            spacing: Style.spacing.xs
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            model: root.screenReceivers

            delegate: Rectangle {
              id: receiverRow
              required property var modelData
              readonly property bool selected: modelData.address === root.selectedAddress
              readonly property bool paired: modelData.paired === true
              readonly property bool hovered: rowClick.containsMouse

              width: screenListView.width
              implicitHeight: receiverContent.implicitHeight + Style.spacing.md * 2
              radius: Style.cornerRadius
              color: selected
                ? Style.hoverFillFor(Color.accent, root.foreground)
                : (hovered ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent")
              border.width: selected ? 1 : 0
              border.color: selected ? Color.accent : "transparent"

              Item {
                id: receiverContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.rightMargin: Style.spacing.rowPaddingX
                implicitHeight: Math.max(receiverLabels.implicitHeight, actionRow.implicitHeight)

                Text {
                  id: receiverGlyph
                  text: receiverRow.paired ? "󰄬" : "󰐨"
                  color: receiverRow.paired ? Color.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                }

                Column {
                  id: receiverLabels
                  anchors.left: receiverGlyph.right
                  anchors.leftMargin: Style.spacing.md
                  anchors.right: actionRow.left
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxs

                  Text {
                    width: parent.width
                    text: receiverRow.modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Row {
                    spacing: Style.spacing.xs

                    Rectangle {
                      height: 14
                      width: protocolLabel.implicitWidth + 8
                      radius: 3
                      color: {
                        var proto = receiverRow.modelData.protocol || "airplay"
                        if (proto === "cast") return "#e67e22"
                        return Color.accent
                      }
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        id: protocolLabel
                        anchors.centerIn: parent
                        text: {
                          var proto = receiverRow.modelData.protocol || "airplay"
                          if (proto === "cast") return "Google Cast"
                          return "AirPlay 2"
                        }
                        color: "#ffffff"
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        font.bold: true
                      }
                    }

                    Text {
                      text: receiverRow.modelData.address
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }

                MouseArea {
                  id: rowClick
                  anchors.left: parent.left
                  anchors.right: actionRow.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.hostWidget) return
                    if (receiverRow.selected) root.hostWidget.clearSelection()
                    else root.hostWidget.selectReceiver(receiverRow.modelData.name, receiverRow.modelData.address, receiverRow.modelData.deviceId, receiverRow.modelData.protocol)
                  }
                }

                Row {
                  id: actionRow
                  spacing: Style.spacing.xs
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter

                  PanelActionButton {
                    iconText: root.mirroring && receiverRow.selected ? "󰓛" : "󰐨"
                    tooltipText: root.mirroring && receiverRow.selected ? root.t("stopTooltip") : root.t("mirrorTooltip")
                    foreground: root.foreground
                    hoverColor: root.mirroring && receiverRow.selected ? Color.urgent : Color.accent
                    fontFamily: root.fontFamily
                    onClicked: {
                      if (!root.hostWidget) return
                      if (root.mirroring && receiverRow.selected) root.hostWidget.stop()
                      else {
                        root.hostWidget.selectReceiver(receiverRow.modelData.name, receiverRow.modelData.address, receiverRow.modelData.deviceId, receiverRow.modelData.protocol)
                        root.hostWidget.start("")
                      }
                    }
                  }

                  PanelActionButton {
                    iconText: "󰆴"
                    tooltipText: root.t("forgetTooltip")
                    foreground: root.foreground
                    hoverColor: Color.urgent
                    visible: receiverRow.paired && (receiverRow.modelData.protocol === "airplay" || !receiverRow.modelData.protocol)
                    fontFamily: root.fontFamily
                    onClicked: if (root.hostWidget) root.hostWidget.forgetReceiver(receiverRow.modelData)
                  }
                }
              }
            }
          }

          // Pairing Box
          Column {
            visible: root.selectedAddress !== "" && root.pairingRequired
            width: parent.width
            spacing: Style.spacing.sm

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: root.t("pairNewReceiver")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              text: root.t("pinHelp")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              spacing: Style.spacing.sm

              TextField {
                id: pairingCode
                width: Style.space(120)
                placeholderText: root.t("pin")
                maximumLength: 4
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegularExpressionValidator { regularExpression: /\d{0,4}/ }
                onAccepted: pairButton.clicked()
              }

              Button {
                id: pairButton
                text: root.t("pairAndConnect")
                enabled: root.selectedAddress !== "" && pairingCode.text.length === 4
                onClicked: {
                  if (root.hostWidget) root.hostWidget.pair(pairingCode.text)
                  pairingCode.text = ""
                }
              }
            }
          }
        }

        // ==========================================
        // TAB 2: DEDICATED MIRACAST / WIDI VIEW
        // ==========================================
        Column {
          visible: root.mainTab === "miracast"
          width: parent.width
          spacing: Style.spacing.panelGap

          Rectangle {
            width: parent.width
            implicitHeight: wfdCardCol.implicitHeight + Style.spacing.md * 2
            radius: Style.cornerRadius
            color: Style.hoverFillFor("#9b59b6", root.foreground)
            border.color: "#9b59b6"
            border.width: 1

            Column {
              id: wfdCardCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.spacing.rowPaddingX
              spacing: Style.spacing.sm

              Row {
                width: parent.width
                spacing: Style.spacing.sm

                Text {
                  text: "󰖟"
                  color: "#9b59b6"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  width: parent.width - Style.space(36)
                  spacing: Style.spacing.xxs

                  Text {
                    text: root.t("miracastSpotTitle")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    text: root.t("miracastSpotDesc")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }
              }

              Button {
                width: parent.width
                text: root.t("launchMiracastBtn")
                onClicked: {
                  if (root.hostWidget && root.hostWidget.launchMiracast) {
                    root.hostWidget.launchMiracast()
                  }
                }
              }
            }
          }

          PanelSectionHeader {
            text: "DISCOVERED WIDI DISPLAYS (" + root.miracastReceivers.length + ")"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: root.miracastReceivers.length === 0
            width: parent.width
            text: "No direct Wi-Fi Direct/Miracast TVs found yet. Click 'Launch Wireless Display' to start P2P streaming."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          ListView {
            id: miracastListView
            width: parent.width
            height: Math.min(contentHeight, Style.space(260))
            spacing: Style.spacing.xs
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            model: root.miracastReceivers

            delegate: Rectangle {
              required property var modelData
              width: miracastListView.width
              implicitHeight: Style.space(48)
              radius: Style.cornerRadius
              color: Style.hoverFillFor(root.foreground, root.foreground)

              Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.spacing.rowPaddingX
                spacing: Style.spacing.md

                Text {
                  text: "󰖟"
                  color: "#9b59b6"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  width: parent.width - Style.space(80)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    text: modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    text: modelData.address
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Button {
                  text: "Cast"
                  anchors.verticalCenter: parent.verticalCenter
                  onClicked: {
                    if (root.hostWidget) {
                      root.hostWidget.selectReceiver(modelData.name, modelData.address, modelData.deviceId, "wfd")
                      root.hostWidget.start("")
                    }
                  }
                }
              }
            }
          }
        }

        // ==========================================
        // TAB 3: HOMEPODS & AUDIO MULTI-ROOM VIEW
        // ==========================================
        Column {
          visible: root.mainTab === "audio"
          width: parent.width
          spacing: Style.spacing.panelGap

          Row {
            width: parent.width
            spacing: Style.spacing.sm

            Button {
              width: (parent.width - Style.spacing.sm) / 2
              text: root.t("selectAll")
              onClicked: {
                if (root.hostWidget && root.hostWidget.enableAllHomepods) {
                  root.hostWidget.enableAllHomepods()
                }
              }
            }

            Button {
              width: (parent.width - Style.spacing.sm) / 2
              text: root.t("turnOffAll")
              onClicked: {
                if (root.hostWidget && root.hostWidget.disableAllHomepods) {
                  root.hostWidget.disableAllHomepods()
                }
                if (root.hostWidget && root.hostWidget.ctlPath) {
                  Quickshell.execDetached([root.hostWidget.ctlPath, "set-sink", "default"])
                }
                Quickshell.execDetached(["omarchy-notification-send", "-g", "󰓃", root.t("audioOutputSwitched"), root.t("useSpeakers")])
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.spacing.sm

            Button {
              width: (parent.width - Style.spacing.sm) / 2
              text: root.t("useHomepods")
              onClicked: {
                if (root.hostWidget && root.hostWidget.ctlPath) {
                  Quickshell.execDetached([root.hostWidget.ctlPath, "set-sink", "homepods"])
                }
                Quickshell.execDetached(["omarchy-notification-send", "-g", "󰓃", root.t("audioOutputSwitched"), root.t("useHomepods")])
              }
            }

            Button {
              width: (parent.width - Style.spacing.sm) / 2
              text: root.t("useSpeakers")
              onClicked: {
                if (root.hostWidget && root.hostWidget.ctlPath) {
                  Quickshell.execDetached([root.hostWidget.ctlPath, "set-sink", "default"])
                }
                Quickshell.execDetached(["omarchy-notification-send", "-g", "󰓃", root.t("audioOutputSwitched"), root.t("useSpeakers")])
              }
            }
          }

          PanelSectionHeader {
            text: root.t("homepodsHeader") + " (" + root.homepodOutputs.length + ")"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: root.homepodOutputs.length === 0
            width: parent.width
            text: "No HomePods or AirPlay 2 speakers discovered. Make sure OwnTone daemon is running."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // Smooth ListView for HomePods & Audio
          ListView {
            id: audioListView
            width: parent.width
            height: Math.min(contentHeight, Style.space(360))
            spacing: Style.spacing.xs
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            model: root.homepodOutputs

            delegate: Rectangle {
              id: speakerRow
              required property var modelData
              readonly property bool isSelected: modelData.selected === true

              width: audioListView.width
              implicitHeight: speakerContent.implicitHeight + Style.spacing.sm * 2
              radius: Style.cornerRadius
              scale: rowClick.pressed ? 0.985 : 1.0
              color: isSelected ? Style.hoverFillFor(Color.accent, root.foreground) : (rowClick.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent")
              border.color: isSelected ? Color.accent : "transparent"
              border.width: isSelected ? 1 : 0

              Behavior on scale { NumberAnimation { duration: 75; easing.type: Easing.OutQuad } }
              Behavior on color { ColorAnimation { duration: 75 } }
              Behavior on border.color { ColorAnimation { duration: 75 } }

              Column {
                id: speakerContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.spacing.rowPaddingX
                spacing: Style.spacing.xs

                Item {
                  width: parent.width
                  height: Style.space(36)

                  MouseArea {
                    id: rowClick
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.hostWidget && root.hostWidget.toggleHomepod) {
                        root.hostWidget.toggleHomepod(modelData.id)
                      }
                    }
                  }

                  Text {
                    id: speakerGlyph
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰓃"
                    color: speakerRow.isSelected ? Color.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                  }

                  Column {
                    anchors.left: speakerGlyph.right
                    anchors.leftMargin: Style.spacing.md
                    anchors.right: checkmarkBox.left
                    anchors.rightMargin: Style.spacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xxs

                    Text {
                      width: parent.width
                      text: modelData.name || "HomePod"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: speakerRow.isSelected
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: modelData.type + (speakerRow.isSelected ? (" • " + (modelData.volume || 100) + "%") : "")
                      color: speakerRow.isSelected ? Color.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Rectangle {
                    id: checkmarkBox
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(20)
                    height: Style.space(20)
                    radius: Style.space(10)
                    color: speakerRow.isSelected ? Color.accent : "transparent"
                    border.color: speakerRow.isSelected ? Color.accent : root.dim
                    border.width: 1.5

                    Text {
                      anchors.centerIn: parent
                      visible: speakerRow.isSelected
                      text: "✓"
                      color: "#ffffff"
                      font.pixelSize: 10
                      font.bold: true
                    }
                  }
                }

                PanelSlider {
                  visible: speakerRow.isSelected
                  bar: root.bar
                  width: parent.width
                  minimum: 0
                  maximum: 100
                  step: 5
                  integer: true
                  value: modelData.volume !== undefined ? modelData.volume : 100
                  onMoved: function(v) {
                    if (root.hostWidget && root.hostWidget.setHomepodVolume) {
                      root.hostWidget.setHomepodVolume(modelData.id, Math.round(v))
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
