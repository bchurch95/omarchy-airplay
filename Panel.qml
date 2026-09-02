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
  property string activeTab: "all"

  readonly property var filteredReceivers: {
    if (root.activeTab === "all") return root.receivers
    return root.receivers.filter(function(r) {
      var proto = r.protocol || "airplay"
      return proto === root.activeTab
    })
  }

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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        WheelHandler {
          target: scroller
          property: "contentY"
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          orientation: Qt.Vertical
          onWheel: function(event) {
            var step = 90
            var dy = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y
            var maxScroll = Math.max(0, scroller.contentHeight - scroller.height)
            var targetY = Math.max(0, Math.min(maxScroll, scroller.contentY - (dy > 0 ? step : -step)))
            scrollAnim.to = targetY
            scrollAnim.restart()
          }
        }

        NumberAnimation {
          id: scrollAnim
          target: scroller
          property: "contentY"
          duration: 120
          easing.type: Easing.OutQuad
        }

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
                text: "󰐨"
                color: root.mirroring ? Color.accent : root.foreground
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

          PanelSeparator { visible: root.homepodOutputs.length > 0; foreground: root.foreground }

          PanelSectionHeader {
            visible: root.homepodOutputs.length > 0
            text: root.t("homepodsHeader")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.homepodOutputs

            delegate: Rectangle {
              id: speakerRow
              required property var modelData
              readonly property bool isSelected: modelData.selected === true

              width: contentColumn.width
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
                    anchors.leftMargin: Style.spacing.lg
                    anchors.right: checkmarkBox.left
                    anchors.rightMargin: Style.spacing.lg
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

          Row {
            visible: root.homepodOutputs.length > 0
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
            visible: root.homepodOutputs.length > 0
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

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: root.t("receivers")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.spacing.xs

            Repeater {
              model: [
                { id: "all", label: root.t("allReceivers") + " (" + root.receivers.length + ")", icon: "󰕰" },
                { id: "airplay", label: root.t("airplayReceivers") + " (" + root.airplayCount + ")", icon: "󰐨" },
                { id: "wfd", label: root.t("miracastReceivers") + " (" + root.wfdCount + ")", icon: "󰖟" },
                { id: "cast", label: root.t("castReceivers") + " (" + root.castCount + ")", icon: "󰑈" }
              ]

              delegate: Rectangle {
                id: tabBtn
                required property var modelData
                readonly property bool isCurrent: root.activeTab === modelData.id
                width: (contentColumn.width - Style.spacing.xs * 3) / 4
                height: Style.space(28)
                radius: Style.cornerRadius
                color: isCurrent ? Color.accent : (tabMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent")
                border.width: isCurrent ? 0 : 1
                border.color: isCurrent ? "transparent" : root.dim

                Row {
                  anchors.centerIn: parent
                  spacing: 4

                  Text {
                    text: tabBtn.modelData.icon
                    color: tabBtn.isCurrent ? "#ffffff" : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: tabBtn.modelData.label
                    color: tabBtn.isCurrent ? "#ffffff" : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.bold: tabBtn.isCurrent
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  id: tabMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.activeTab = tabBtn.modelData.id
                }
              }
            }
          }

          Rectangle {
            visible: root.activeTab === "wfd" || (root.activeTab === "all" && root.wfdCount === 0)
            width: contentColumn.width
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
              spacing: Style.spacing.xs

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

          Text {
            visible: root.discoveryError !== ""
            width: parent.width
            text: root.discoveryError
            color: root.discoveryError === root.t("noReceivers") ? root.dim : Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.filteredReceivers

            delegate: Rectangle {
              id: receiverRow
              required property var modelData
              readonly property bool selected: modelData.address === root.selectedAddress
              readonly property bool paired: modelData.paired === true
              readonly property bool hovered: rowClick.containsMouse

              width: contentColumn.width
              implicitHeight: receiverContent.implicitHeight + Style.spacing.lg * 2
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
                  anchors.leftMargin: Style.spacing.lg
                  anchors.right: actionRow.left
                  anchors.rightMargin: Style.spacing.lg
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
                        if (proto === "wfd") return "#9b59b6"
                        return Color.accent
                      }
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        id: protocolLabel
                        anchors.centerIn: parent
                        text: {
                          var proto = receiverRow.modelData.protocol || "airplay"
                          if (proto === "cast") return "Google Cast"
                          if (proto === "wfd") return "Miracast"
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

          PanelSeparator { visible: root.selectedAddress !== "" && root.pairingRequired; foreground: root.foreground }

          PanelSectionHeader {
            visible: root.selectedAddress !== "" && root.pairingRequired
            text: root.t("pairNewReceiver")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: root.selectedAddress !== "" && root.pairingRequired
            width: parent.width
            text: root.t("pinHelp")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Row {
            visible: root.selectedAddress !== "" && root.pairingRequired
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
    }
  }
}
