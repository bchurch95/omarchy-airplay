import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "i18n/I18n.js" as I18n

BarWidget {
  id: root
  moduleName: "io.github.etroll.omarchy-airplay"

  readonly property string ctlPath: String(Qt.resolvedUrl("bin/omarchy-airplay-ctl")).replace(/^file:\/\//, "")
  readonly property string localeName: Qt.locale().name

  property var receivers: []
  property string selectedName: ""
  property string selectedAddress: ""
  property string selectedDeviceId: ""
  property string selectedProtocol: "airplay"
  property bool pairingRequired: false
  property bool pairingPromptActive: false
  property string discoveryError: ""
  property string streamError: ""
  property string networkDescription: ""
  property string firewallError: ""
  property bool firewallManaged: false
  property string forgettingAddress: ""
  property bool deliberateStop: false
  property string queuedPairCode: ""
  property string pendingStartPairCode: ""
  property bool pairingAttemptInFlight: false

  readonly property bool mirroring: mirrorProcess.running
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  property var homepodOutputs: []
  property int homepodActiveCount: 0

  readonly property var mirroredProperties: [
    "bar", "settings", "receivers", "selectedName", "selectedAddress",
    "selectedDeviceId", "selectedProtocol", "pairingRequired", "pairingPromptActive", "discoveryError", "streamError", "mirroring",
    "networkDescription", "firewallError", "firewallManaged", "homepodOutputs", "homepodActiveCount"
  ]

  function refreshHomepods() {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "http://localhost:3689/api/outputs", true)
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
        try {
          var res = JSON.parse(xhr.responseText)
          if (res && res.outputs) {
            var count = 0
            var list = []
            for (var i = 0; i < res.outputs.length; i++) {
              var out = res.outputs[i]
              var name = out.name || ""
              if (out.id !== "0" && name.indexOf("MacBook") === -1) {
                list.push(out)
                if (out.selected) count++
              }
            }
            root.homepodOutputs = list
            root.homepodActiveCount = count
            root.injectPanel()
          }
        } catch (e) {}
      }
    }
    xhr.send()
  }

  function setHomepodVolume(id, vol) {
    for (var i = 0; i < root.homepodOutputs.length; i++) {
      if (root.homepodOutputs[i].id === id) {
        root.homepodOutputs[i].volume = Math.round(vol)
      }
    }
    var xhr = new XMLHttpRequest()
    xhr.open("PUT", "http://localhost:3689/api/outputs/" + id, true)
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.send(JSON.stringify({ volume: Math.round(vol) }))
  }

  function toggleHomepod(id) {
    var anyActive = false
    for (var i = 0; i < root.homepodOutputs.length; i++) {
      if (root.homepodOutputs[i].id === id) {
        root.homepodOutputs[i].selected = !root.homepodOutputs[i].selected
      }
      if (root.homepodOutputs[i].selected) anyActive = true
    }
    root.injectPanel()

    var xhr = new XMLHttpRequest()
    xhr.open("PUT", "http://localhost:3689/api/outputs/" + id + "/toggle", true)
    xhr.timeout = 2500
    xhr.ontimeout = function() { root.refreshHomepods() }
    xhr.onerror = function() { root.refreshHomepods() }
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        root.refreshHomepods()
      }
    }
    xhr.send()

    if (anyActive) {
      Quickshell.execDetached([root.ctlPath, "set-sink", "homepods"])
      var pXhr = new XMLHttpRequest()
      pXhr.open("PUT", "http://localhost:3689/api/player/play", true)
      pXhr.send()
    } else {
      Quickshell.execDetached([root.ctlPath, "set-sink", "default"])
    }
  }

  function enableAllHomepods() {
    var ids = []
    for (var i = 0; i < root.homepodOutputs.length; i++) {
      var name = root.homepodOutputs[i].name || ""
      if (name.indexOf("ATV") === -1 && name.indexOf("MacBook") === -1 && name.indexOf("Test") === -1 && name.indexOf("Bar") === -1) {
        ids.push(root.homepodOutputs[i].id)
        root.homepodOutputs[i].selected = true
      }
    }
    root.injectPanel()

    var xhr = new XMLHttpRequest()
    xhr.open("PUT", "http://localhost:3689/api/outputs/set", true)
    xhr.timeout = 3000
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.ontimeout = function() { root.refreshHomepods() }
    xhr.onerror = function() { root.refreshHomepods() }
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) root.refreshHomepods()
    }
    xhr.send(JSON.stringify({ outputs: ids }))
    Quickshell.execDetached([root.ctlPath, "set-sink", "homepods"])
    var pXhr = new XMLHttpRequest()
    pXhr.open("PUT", "http://localhost:3689/api/player/play", true)
    pXhr.send()
  }

  function disableAllHomepods() {
    for (var i = 0; i < root.homepodOutputs.length; i++) {
      root.homepodOutputs[i].selected = false
    }
    root.injectPanel()

    var xhr = new XMLHttpRequest()
    xhr.open("PUT", "http://localhost:3689/api/outputs/set", true)
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) root.refreshHomepods()
    }
    xhr.send(JSON.stringify({ outputs: [] }))
    Quickshell.execDetached([root.ctlPath, "set-sink", "default"])
  }

  function boolSetting(key, fallback) {
    var value = root.setting(key, fallback)
    if (typeof value === "boolean") return value
    return String(value).toLowerCase() === "true"
  }

  function t(key, values) { return I18n.t(root.localeName, key, values) }

  function notify(title, message) {
    Quickshell.execDetached(["omarchy-notification-send", "-g", "󰐨", title, message])
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    for (var i = 0; i < root.mirroredProperties.length; i++) {
      var name = root.mirroredProperties[i]
      if (name in target) target[name] = root[name]
    }
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
    root.discover()
    root.refreshNetwork()
    root.refreshHomepods()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (root.opened) root.close()
    else root.open()
  }

  function discover() {
    if (discoverProcess.running) return
    root.discoveryError = ""
    discoverProcess.command = [root.ctlPath, "discover"]
    discoverProcess.running = true
    root.injectPanel()
  }

  function parseReceivers(text) {
    var found = []
    var lines = String(text).trim().split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (lines[i] === "") continue
      var fields = lines[i].split("\t")
      if (fields.length >= 2) found.push({
        name: fields[0],
        address: fields[1],
        deviceId: fields[2] || "",
        paired: fields[3] === "1",
        protocol: fields[4] || "airplay"
      })
    }
    return found
  }

  function selectReceiver(name, address, deviceId, protocol) {
    root.selectedName = name
    root.selectedAddress = address
    root.selectedDeviceId = deviceId || ""
    root.selectedProtocol = protocol || "airplay"
    root.pairingPromptActive = true
    for (var i = 0; i < root.receivers.length; i++) {
      if (root.receivers[i].address === address) {
        root.pairingRequired = !root.receivers[i].paired && (root.selectedProtocol === "airplay")
      }
    }
    saveProcess.command = [root.ctlPath, "save", name, address, root.selectedDeviceId]
    saveProcess.running = true
    if (root.selectedProtocol === "airplay") {
      root.checkPairing()
      root.refreshFirewallState()
    } else {
      root.pairingRequired = false
    }
    root.injectPanel()
  }

  function refreshNetwork() {
    networkProcess.command = [root.ctlPath, "network"]
    networkProcess.running = true
  }

  function refreshFirewallState() {
    root.firewallManaged = false
    root.firewallError = ""
    if (root.selectedDeviceId === "") { root.injectPanel(); return }
    firewallLoadProcess.command = [root.ctlPath, "firewall-load", root.selectedDeviceId]
    firewallLoadProcess.running = true
  }

  function allowSelectedReceiver() {
    if (root.selectedDeviceId === "" || root.selectedAddress === "") return "no-receiver"
    root.firewallError = ""
    firewallAllowProcess.command = ["pkexec", "/usr/bin/ufw", "allow", "from", root.selectedAddress,
      "to", "any", "port", String(root.setting("portRange", "60000-60010")).replace("-", ":")]
    firewallAllowProcess.running = true
    root.injectPanel()
    return "authorizing-firewall"
  }

  function clearSelection() {
    if (root.mirroring) root.stop()
    root.selectedName = ""
    root.selectedAddress = ""
    root.selectedDeviceId = ""
    root.selectedProtocol = "airplay"
    root.pairingRequired = false
    root.pairingPromptActive = false
    clearProcess.command = [root.ctlPath, "clear"]
    clearProcess.running = true
    root.injectPanel()
  }

  function checkPairing() {
    if (root.selectedDeviceId === "") {
      root.pairingRequired = true
      root.injectPanel()
      return
    }
    pairingCheckProcess.command = [root.ctlPath, "paired", root.selectedDeviceId]
    pairingCheckProcess.running = true
  }

  function forgetReceiver(receiver) {
    if (!receiver || receiver.deviceId === "") {
      root.streamError = root.t("pairingCannotForget")
      root.injectPanel()
      return
    }
    if (root.mirroring && receiver.address === root.selectedAddress) root.stop()
    root.forgettingAddress = receiver.address
    pendingForgetReceiver = receiver
    firewallLookupForForgetProcess.command = [root.ctlPath, "firewall-load", receiver.deviceId]
    firewallLookupForForgetProcess.running = true
    if (receiver.address === root.selectedAddress) {
      root.pairingRequired = true
      root.pairingPromptActive = false
      root.injectPanel()
    }
  }

  function setReceiverPairing(address, paired) {
    var updated = []
    for (var i = 0; i < root.receivers.length; i++) {
      var receiver = root.receivers[i]
      updated.push({
        name: receiver.name,
        address: receiver.address,
        deviceId: receiver.deviceId,
        paired: receiver.address === address ? paired : receiver.paired,
        protocol: receiver.protocol || "airplay"
      })
    }
    root.receivers = updated
    if (root.selectedAddress === address && root.selectedProtocol === "airplay") root.pairingRequired = !paired
    root.injectPanel()
  }

  function streamCommand(pairCode) {
    var proto = root.selectedProtocol || "airplay"
    if (proto === "wfd") {
      return ["fluxcast", "--protocol", "wfd", "--device", root.selectedDeviceId || root.selectedAddress]
    }
    if (proto === "cast") {
      return ["fluxcast", "--protocol", "cast", "--device", root.selectedAddress]
    }
    var command = ["env"]
    var vaapiDriver = String(root.setting("vaapiDriver", ""))
    if (vaapiDriver !== "") command.push("LIBVA_DRIVER_NAME=" + vaapiDriver)
    command.push(String(root.setting("doubletakePath", "doubletake")))
    command.push("-target", root.selectedAddress)
    command.push("-port-range", String(root.setting("portRange", "60000-60010")))
    command.push("-video-codec", String(root.setting("videoCodec", "h264")))
    command.push("-hwaccel", String(root.setting("hardwareEncoder", "auto")))
    command.push("-fps", String(root.setting("fps", 30)))
    command.push("-target-latency-ms", String(root.setting("targetLatencyMs", 0)))
    if (!root.boolSetting("audio", true)) command.push("-no-audio")
    if (pairCode !== "") command.push("-pair", "-code", pairCode)
    return command
  }

  function launchStream(pairCode) {
    root.streamError = ""
    root.deliberateStop = false
    mirrorProcess.command = root.streamCommand(pairCode || "")
    mirrorProcess.running = true
    root.notify(root.t("mirroringTitle"), root.t("connecting", { name: root.selectedName }))
    root.injectPanel()
    return "starting"
  }

  function start(pairCode) {
    if (root.mirroring) {
      root.stop(true)
    }
    if (clearRestoreProcess.running) return "preparing-capture"
    if (root.selectedAddress === "") {
      root.open()
      return "no-receiver"
    }
    if ((pairCode || "") === "") root.pairingPromptActive = true
    root.pendingStartPairCode = pairCode || ""
    if (root.boolSetting("alwaysPromptForCapture", false) && root.selectedDeviceId !== "") {
      clearRestoreProcess.command = [root.ctlPath, "clear-restore", root.selectedDeviceId]
      clearRestoreProcess.running = true
      return "preparing-capture"
    }
    return root.launchStream(root.pendingStartPairCode)
  }

  function stop(silent) {
    root.deliberateStop = true
    mirrorProcess.running = false
    Quickshell.execDetached(["killall", "doubletake"])
    if (!silent) root.notify(root.t("mirroringTitle"), root.t("stopped", { name: root.selectedName }))
    root.injectPanel()
    return "stopping"
  }

  function pair(code) {
    var clean = String(code).replace(/\s/g, "")
    if (!/^\d{4}$/.test(clean)) return "invalid-code"
    root.setReceiverPairing(root.selectedAddress, true)
    root.pairingPromptActive = false
    root.pairingAttemptInFlight = true
    pairingCompleteTimer.restart()
    if (root.mirroring) {
      root.queuedPairCode = clean
      root.stop(true)
      return "restarting-for-pairing"
    }
    return root.start(clean)
  }

  function toggleStream() {
    if (root.mirroring) return root.stop()
    return root.start("")
  }

  Component.onCompleted: {
    loadProcess.command = [root.ctlPath, "load"]
    loadProcess.running = true
    root.discover()
    root.refreshNetwork()
  }

  onBarChanged: root.injectPanel()
  onSettingsChanged: root.injectPanel()

  Process {
    id: loadProcess
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: loadProcess.outText = text }
    onExited: function(code) {
      if (code === 0) {
        var fields = String(loadProcess.outText).trim().split("\t")
        if (fields.length >= 2) {
          root.selectedName = fields[0]
          root.selectedAddress = fields[1]
          root.selectedDeviceId = fields[2] || ""
          root.checkPairing()
        }
      }
      loadProcess.outText = ""
      root.injectPanel()
    }
  }

  property var pendingForgetReceiver: null

  function finishForget() {
    if (!pendingForgetReceiver) return
    forgetProcess.command = [root.ctlPath, "forget", pendingForgetReceiver.deviceId]
    forgetProcess.running = true
    pendingForgetReceiver = null
  }

  Process {
    id: networkProcess
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: networkProcess.outText = text }
    onExited: function(code) {
      if (code === 0) {
        var fields = String(networkProcess.outText).trim().split("\t")
        root.networkDescription = fields.length >= 4
          ? ((fields[1] || fields[0]) + " · " + (fields[2] || fields[0]) + " · " + fields[3]) : ""
      } else root.networkDescription = ""
      networkProcess.outText = ""
      root.injectPanel()
    }
  }

  Process {
    id: firewallLoadProcess
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: firewallLoadProcess.outText = text }
    onExited: function(code) {
      var fields = String(firewallLoadProcess.outText).trim().split("\t")
      root.firewallManaged = code === 0 && fields.length >= 3 && fields[1] === root.selectedAddress
      firewallLoadProcess.outText = ""
      root.injectPanel()
    }
  }

  Process {
    id: firewallAllowProcess
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: firewallAllowProcess.errText = text }
    onExited: function(code) {
      if (code === 0) {
        firewallSaveProcess.command = [root.ctlPath, "firewall-save", root.selectedDeviceId, root.selectedAddress,
          String(root.setting("portRange", "60000-60010"))]
        firewallSaveProcess.running = true
        root.firewallManaged = true
        root.notify(root.t("firewallAllowedTitle"), root.t("firewallAllowed", { address: root.selectedAddress }))
      } else root.firewallError = root.t("firewallAllowFailed")
      firewallAllowProcess.errText = ""
      root.injectPanel()
    }
  }

  Process { id: firewallSaveProcess }

  Process {
    id: firewallLookupForForgetProcess
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: firewallLookupForForgetProcess.outText = text }
    onExited: function(code) {
      var fields = String(firewallLookupForForgetProcess.outText).trim().split("\t")
      firewallLookupForForgetProcess.outText = ""
      if (code !== 0 || fields.length < 3) { root.finishForget(); return }
      firewallRemoveProcess.command = ["pkexec", "/usr/bin/ufw", "--force", "delete", "allow", "from", fields[1],
        "to", "any", "port", String(fields[2]).replace("-", ":")]
      firewallRemoveProcess.running = true
    }
  }

  Process {
    id: firewallRemoveProcess
    onExited: function(code) {
      if (code === 0 && pendingForgetReceiver) {
        if (pendingForgetReceiver.address === root.selectedAddress) root.firewallManaged = false
        firewallClearProcess.command = [root.ctlPath, "firewall-clear", pendingForgetReceiver.deviceId]
        firewallClearProcess.running = true
        root.finishForget()
      } else {
        root.firewallError = root.t("firewallRemoveFailed")
        pendingForgetReceiver = null
      }
      root.injectPanel()
    }
  }

  Process { id: firewallClearProcess }

  Timer {
    id: pairingCompleteTimer
    interval: 8000
    repeat: false
    onTriggered: {
      root.pairingAttemptInFlight = false
      root.discover()
    }
  }

  Process {
    id: saveProcess
    stderr: StdioCollector { waitForEnd: true }
  }

  Process { id: clearProcess }

  Process {
    id: clearRestoreProcess
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: clearRestoreProcess.errText = text }
    onExited: function(code) {
      if (code === 0) root.launchStream(root.pendingStartPairCode)
      else {
        root.streamError = String(clearRestoreProcess.errText).trim() || root.t("capturePreparationFailed")
        root.injectPanel()
      }
      clearRestoreProcess.errText = ""
    }
  }

  Process {
    id: pairingCheckProcess
    onExited: function(code) {
      root.pairingRequired = code !== 0
      if (root.pairingRequired) root.pairingPromptActive = true
      root.injectPanel()
    }
  }

  Process {
    id: forgetProcess
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: forgetProcess.errText = text }
    onExited: function(code) {
      if (code !== 0) root.streamError = String(forgetProcess.errText).trim() || root.t("pairingForgetFailed")
      else {
        if (root.forgettingAddress === root.selectedAddress) root.firewallManaged = false
        root.notify(root.t("pairingForgottenTitle"), root.t("pairingForgotten"))
        root.discover()
      }
      root.forgettingAddress = ""
      forgetProcess.errText = ""
      root.injectPanel()
    }
  }

  Process {
    id: discoverProcess
    property string outText: ""
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: discoverProcess.outText = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: discoverProcess.errText = text }
    onExited: function(code) {
      if (code === 0) {
        root.receivers = root.parseReceivers(discoverProcess.outText)
        root.discoveryError = root.receivers.length === 0 ? root.t("noReceivers") : ""
      } else {
        root.receivers = []
        root.discoveryError = String(discoverProcess.errText).trim() || root.t("discoveryFailed")
      }
      discoverProcess.outText = ""
      discoverProcess.errText = ""
      root.injectPanel()
    }
  }

  Process {
    id: mirrorProcess
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: mirrorProcess.errText = text }
    onExited: function(code) {
      var wasDeliberate = root.deliberateStop
      root.deliberateStop = false
      if (root.queuedPairCode !== "") {
        var codeToUse = root.queuedPairCode
        root.queuedPairCode = ""
        Qt.callLater(function() { root.start(codeToUse) })
      } else if (!wasDeliberate && code !== 0) {
        if (root.pairingAttemptInFlight) {
          root.pairingAttemptInFlight = false
          pairingCompleteTimer.stop()
          root.setReceiverPairing(root.selectedAddress, false)
          root.pairingPromptActive = true
        }
        root.streamError = root.t("connectionFailed", { code: code })
        root.notify(root.t("connectionFailedTitle"), root.streamError)
      }
      mirrorProcess.errText = ""
      root.injectPanel()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "io.github.etroll.omarchy-airplay"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function discover(): void { root.discover() }
    function select(name: string, address: string, deviceId: string): string {
      root.selectReceiver(name, address, deviceId)
      return "selected " + name + " (" + address + ")"
    }
    function unselect(): void { root.clearSelection() }
    function start(): string { return root.start("") }
    function stop(): string { return root.stop() }
    function toggle(): string { return root.toggleStream() }
    function pair(code: string): string { return root.pair(code) }
    function status(): string {
      if (root.mirroring) return "mirroring " + root.selectedName + " (" + root.selectedAddress + ")"
      if (root.selectedAddress !== "") return "stopped; selected " + root.selectedName + " (" + root.selectedAddress + ")"
      return "stopped; no receiver selected"
    }
  }

  Timer {
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshHomepods()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰐨"
    active: root.mirroring || root.homepodActiveCount > 0
    dimmed: !root.mirroring && root.homepodActiveCount === 0
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.icon
    tooltipText: root.mirroring
      ? root.t("tooltipMirroring", { name: root.selectedName })
      : (root.homepodActiveCount > 0 ? ("HomePods (" + root.homepodActiveCount + " streaming)") : "AirPlay (Screen & HomePods)")
    onPressed: function(mouseButton) {
      root.togglePanel()
    }
  }
}
