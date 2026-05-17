import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import org.qfield
import org.qgis
import Theme

/**
 * QField Nextcloud Auto-Upload Plugin
 * 
 * Uses exclusively the native 'qfield_webdav_configuration.json' as data basis.
 * Provides live network validation via HTTP PROPFIND and triggers the asynchronous 
 * C++ core safely after explicit password assignment. UI completely in English.
 */
Item {
  id: plugin

  // --- QFIELD INTERFACE BINDINGS ---
  property var mainWindow: iface.mainWindow()
  property var busyOverlay: iface.findItemByObjectName('busyOverlay')
  
  // --- STATUS FLAG AGAINST DOUBLE CLICKS ---
  property bool isCurrentlyUploading: false

  // --- INSTANTIATE NATIVE QFIELD WEBDAV COMPONENT ---
  WebdavConnection {
    id: qfieldWebdav
    url: storedUrl
    username: storedUser
    password: storedPass
    storePassword: false

    // Signal handler for native QField transmission progress (0.0 to 1.0)
    onProgressChanged: {
      let percent = Math.round(qfieldWebdav.progress * 100)
      logToQField("  -> C++ Network transfer status: " + percent + "%", 0)
      
      if (busyOverlay && qfieldWebdav.isUploadingPath) {
        busyOverlay.progress = percent
      }

      // Start watchdog ONLY ONCE when 100% is reached locally
      if (percent >= 100) {
        if (!watchdogTimer.running) {
          logToQField("ℹ️ 100% scan reached. Starting network transfer buffer (30s)...", 0)
          watchdogTimer.start() 
        }
      }
    }

    onConfirmationRequested: {
      logToQField("ℹ️ Native confirmationRequested received. Confirming C++ request...", 0)
      qfieldWebdav.confirmRequest() 
    }

    onUploadFinished: (success, message) => {
      logToQField("🏁 Native C++ response received! Success: " + success + " | Message: " + message, 0)
      watchdogTimer.stop() 
      plugin.finalizeUploadEffects(success, message)
    }
  }

  // --- AUTOMATIC WATCHDOG TIMER FOR NETWORK STREAM ---
  Timer {
    id: watchdogTimer
    interval: 30000 // 30 seconds buffer for real network transmission
    repeat: false
    running: false
    onTriggered: {
      logToQField("⏱️ Watchdog buffer expired. Closing UI overlay.", 3)
      plugin.finalizeUploadEffects(true, "Watchdog auto-clear")
    }
  }

  // Central function to clean up UI states
  function finalizeUploadEffects(success, message) {
    plugin.isCurrentlyUploading = false // Release lock
    
    if (busyOverlay) {
      busyOverlay.state = "hidden"
    }
    
    if (success) {
      logToQField("✔ Synchronization completed successfully.", 3)
      mainWindow.displayToast(qsTr("Synchronization successful!"))
    } else {
      logToQField("❌ Synchronization failed: " + message, 2)
      mainWindow.displayToast(qsTr("Error: ") + message)
      
      if (message === "Cancelled" && qfieldWebdav.isUploadingPath) {
        qfieldWebdav.cancelRequest()
      }
    }
  }

  // --- INTERNAL STORAGE VARIABLES (Live from qfield_webdav_configuration.json) ---
  property string storedUrl: ""
  property string storedUser: ""
  property string storedPass: ""
  property string storedStructure: ""
  property string initLogBuffer: ""
  property string testStatusText: ""
  property color testStatusColor: Theme.mainTextColor

  // --- PERSISTENT INTERNAL SETTINGS ---
  Settings {
    id: appSettings
    category: "qfield-nextcloud-native-class-v34"
    property bool autoUploadEnabled: false         
    property int intervalHours: 2        
  }

  // --- CENTRAL LOGGING FUNCTION ---
  function logToQField(message, level) {
    var qglevel = (level !== undefined) ? level : 0
    var prefix = ["ℹ️", "⚠️", "❌", "✔"][qglevel] || "•"
    var formattedMessage = prefix + " " + message
    plugin.initLogBuffer += formattedMessage + "\n"
    if (copyableLogText) {
      copyableLogText.text = plugin.initLogBuffer
    }
    console.log("QField-Plugin-Log: " + formattedMessage)
  }

  // --- ASYNCHRONOUS LIVE LOGIN TEST WITH TEXT FILE UPLOAD VIA HTTP PUT ---
  function testNextcloudConnection(url, user, pass, structure) {
    plugin.testStatusText = qsTr("Checking connection...")
    plugin.testStatusColor = Theme.secondaryTextColor
    
    let cleanUrl = plugin.getFormattedTargetUrl(url) + "remote.php/dav/files/" + user.trim()
    let folderPart = structure.trim()
    if (folderPart !== "" && folderPart !== "/") {
       if (!folderPart.startsWith("/")) folderPart = "/" + folderPart
       cleanUrl = cleanUrl + folderPart
    }
    if (!cleanUrl.endsWith("/")) cleanUrl = cleanUrl + "/"
    
    let testFileUrl = cleanUrl + "qfield_webdav_test.txt"

    let xhr = new XMLHttpRequest()
    xhr.open("PROPFIND", cleanUrl, true)
    
    let authHeader = "Basic " + Qt.btoa(user.trim() + ":" + pass)
    xhr.setRequestHeader("Authorization", authHeader)
    xhr.setRequestHeader("Depth", "0")

    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        logToQField("Base WebDAV HTTP Status: " + xhr.status, 0)
        
        if (xhr.status === 207 || xhr.status === 200) {
          logToQField("✔ Directory reachable. Writing test file...", 0)
          
          let putXhr = new XMLHttpRequest()
          putXhr.open("PUT", testFileUrl, true)
          putXhr.setRequestHeader("Authorization", authHeader)
          putXhr.setRequestHeader("Content-Type", "text/plain; charset=utf-8")
          
          putXhr.onreadystatechange = function() {
            if (putXhr.readyState === XMLHttpRequest.DONE) {
              logToQField("📝 Test file upload HTTP Status: " + putXhr.status, 0)
              if (putXhr.status === 201 || putXhr.status === 204) {
                plugin.testStatusText = "✔ Connection successful! Credentials valid."
                plugin.testStatusColor = "#2ecc71"
                logToQField("✔ File 'qfield_webdav_test.txt' created on Nextcloud.", 3)
              } else {
                plugin.testStatusText = "⚠️ Write permission denied (Status " + putXhr.status + ")"
                plugin.testStatusColor = "#f39c12"
              }
            }
          }
          putXhr.send("QField WebDAV Test Content\nTimestamp: " + new Date().toLocaleString())
          
        } else if (xhr.status === 401) {
          plugin.testStatusText = "❌ Access denied (401). Invalid password or user."
          plugin.testStatusColor = "#e74c3c"
        } else if (xhr.status === 404) {
          plugin.testStatusText = "❌ Directory not found (404)."
          plugin.testStatusColor = "#e74c3c"
        } else {
          plugin.testStatusText = "❌ Error: HTTP Code " + xhr.status
          plugin.testStatusColor = "#e74c3c"
        }
      }
    }
    xhr.send()
  }

  // --- INITIALIZATION ON START ---
  Component.onCompleted: {
    logToQField("Plugin loaded. Initializing native QField WebDAV API...", 0)
    Qt.callLater(function() {
      iface.addItemToDashboardActionsToolbar(uploadButton)
      if (busyOverlay) {
        busyOverlay.actionClicked.connect(cancelUpload)
      }
    })
    plugin.loadCredentialsFromJSON()
  }

  Component.onDestruction: {
    if (busyOverlay) {
      busyOverlay.actionClicked.disconnect(cancelUpload)
    }
    watchdogTimer.stop()
    uploadTimer.stop()
  }

  function configure() {
    settingsDialog.open()
  }

  Timer {
    id: uploadTimer
    repeat: true
    running: appSettings.autoUploadEnabled
    interval: appSettings.intervalHours * 3600000
    onTriggered: {
      plugin.loadCredentialsFromJSON()
      triggerManualUpload() 
    }
  }

  // --- RECONSTRUCT PATH FROM PROJECT API ---
  function getProjectDirectory() {
    var rawPath = qgisProject.fileName ? qgisProject.fileName.toString() : ""
    if (rawPath === "") return ""
    if (rawPath.startsWith("file://")) rawPath = rawPath.substring(7)
    rawPath = decodeURIComponent(rawPath).replace(/\\/g, "/")
    return rawPath.substring(0, rawPath.lastIndexOf('/'))
  }

  function getProjectFileNameOnly() {
    var rawPath = qgisProject.fileName ? qgisProject.fileName.toString() : ""
    if (rawPath.startsWith("file://")) rawPath = rawPath.substring(7)
    rawPath = decodeURIComponent(rawPath).replace(/\\/g, "/")
    return rawPath.substring(rawPath.lastIndexOf('/') + 1)
  }

  function getFormattedTargetUrl(baseUrl) {
    let cleanUrl = baseUrl.toString().trim()
    if (!cleanUrl.startsWith("http://") && !cleanUrl.startsWith("https://")) {
      cleanUrl = "https://" + cleanUrl
    }
    if (!cleanUrl.endsWith("/")) cleanUrl = cleanUrl + "/"
    return cleanUrl
  }

  Connections {
    target: qgisProject ? qgisProject : null
    ignoreUnknownSignals: true
    function onFileNameChanged() {
      plugin.loadCredentialsFromJSON()
    }
  }

  // --- NATIVE TRANSMISSION OF THE PROJECT DIRECTORY ---
  function triggerManualUpload() {
    if (plugin.isCurrentlyUploading) return
    plugin.isCurrentlyUploading = true 

    let localDir = plugin.getProjectDirectory()
    logToQField("🚀 Upload started. Locating local project directory: " + localDir, 0)
    
    if (!localDir || localDir === "" || plugin.storedUser === "") {
      mainWindow.displayToast(qsTr("Please verify Nextcloud configuration settings."))
      plugin.isCurrentlyUploading = false
      return
    }

    let baseUrl = plugin.getFormattedTargetUrl(plugin.storedUrl) 
    let username = plugin.storedUser.trim()
    let folderPart = plugin.storedStructure.trim()
    
    if (!folderPart.startsWith("/")) folderPart = "/" + folderPart
    if (!folderPart.endsWith("/")) folderPart = folderPart + "/"
    
    let fullTargetUrl = baseUrl + "remote.php/dav/files/" + username + folderPart

    // --- C++ VALIDATION: WRITE EXPECTED CONFIG STRUCTURE ---
    let webdavConfigPath = localDir + "/qfield_webdav_configuration.json"
    try {
      let webdavConfig = {
        "remote_path": folderPart,
        "url": baseUrl + "remote.php/dav/files/" + username, 
        "username": username,
        "password": plugin.storedPass 
      }
      let configString = JSON.stringify(webdavConfig, null, 4)
      FileUtils.writeFileContent(webdavConfigPath, configString)
      logToQField("ℹ️ Native C++ configuration file generated (qfield_webdav_configuration.json)", 0)
    } catch(err) {
      logToQField("⚠️ Error writing C++ configuration file: " + err, 1)
    }

    logToQField("Step 1: Initializing C++ connection parameters...", 0)
    qfieldWebdav.url = fullTargetUrl
    qfieldWebdav.username = username
    qfieldWebdav.password = plugin.storedPass

    logToQField("Step 2: Verification target path -> " + fullTargetUrl, 0)

    if (busyOverlay) {
      busyOverlay.text = qsTr("Synchronizing project folder via QField WebDAV...")
      busyOverlay.showProgress = true
      busyOverlay.progress = 0
      busyOverlay.state = "visible"
    }

    let pathsToUpload = [ localDir ]
    logToQField("Step 3: Local path array prepared. Elements: " + pathsToUpload.length, 0)
    
    Qt.callLater(function() {
      logToQField("Step 4: Dispatching asynchronous uploadPaths() to C++ engine...", 0)
      try {
        qfieldWebdav.uploadPaths(pathsToUpload) 
        logToQField("Step 5: uploadPaths() successfully delegated to C++ core.", 0)
      } catch(err) {
        plugin.isCurrentlyUploading = false
        logToQField("❌ Critical exception during uploadPaths execution: " + err, 2)
      }
    })
  }

  // --- WRITE CONFIGURATION TO THE FILE SYSTEM ---
  function saveCredentialsToJSON() {
    var dir = getProjectDirectory()
    if (!dir) return
    var jsonPath = dir + "/qfield_webdav_configuration.json"
    
    let folderPart = structureField.text.toString().trim()
    if (!folderPart.startsWith("/")) folderPart = "/" + folderPart
    if (!folderPart.endsWith("/")) folderPart = folderPart + "/"

    let baseUrl = plugin.getFormattedTargetUrl(urlField.text.toString())
    let username = userField.text.toString().trim()
    let fullTargetUrl = baseUrl + "remote.php/dav/files/" + username + folderPart
    if (fullTargetUrl.endsWith("/")) fullTargetUrl = fullTargetUrl.slice(0, -1)

    var settingsData = {
        "remote_path": folderPart,
        "url": baseUrl + "remote.php/dav/files/" + username, 
        "username": username,
        "password": passField.text.toString()
    }
    try {
        var jsonString = JSON.stringify(settingsData, null, 4)
        FileUtils.writeFileContent(jsonPath, jsonString)
        logToQField("qfield_webdav_configuration.json successfully overwritten.", 0)
    } catch (e) { logToQField("Error writing JSON file: " + e, 2) }
  }

  // --- READ NATIVE CONFIGURATION FROM THE FILE SYSTEM ---
  function loadCredentialsFromJSON() {
    var dir = getProjectDirectory()
    if (!dir || dir === "") return false
    var jsonPath = dir + "/qfield_webdav_configuration.json"
    try {
      if (!FileUtils.fileExists(jsonPath)) return false
      var rawContent = FileUtils.readFileContent(jsonPath)
      var contentString = "" + rawContent 
      if (contentString !== "") {
        var config = JSON.parse(contentString)
        
        let fullUrl = config.url ? config.url.toString() : "https://cloud.de"
        if (fullUrl.includes("/remote.php/dav/files/")) {
          let parts = fullUrl.split("/remote.php/dav/files/")
          plugin.storedUrl = parts[0]
        } else {
          plugin.storedUrl = fullUrl
        }
        
        plugin.storedUser = config.username ? config.username.toString() : ""
        plugin.storedPass = config.password ? config.password.toString() : "" 
        plugin.storedStructure = config.remote_path ? config.remote_path.toString() : "/Qfield/"
        
        logToQField("Native JSON loaded. User: " + plugin.storedUser + " | Remote Path: " + plugin.storedStructure, 0)
        return true
      }
    } catch (e) { logToQField("Error reading JSON file: " + e, 2) }
    return false
  }

  function cancelUpload() {
    logToQField("⚠️ Upload operation cancelled by user.", 1)
    plugin.finalizeUploadEffects(false, "Cancelled")
  }

  // --- USER INTERFACE COMPONENTS ---
  QfToolButton {
    id: uploadButton; height: 48; width: 48
    iconSource: Qt.resolvedUrl("icon.svg")
    iconColor: Theme.mainTextColor; bgcolor: "transparent"
    
    enabled: !plugin.isCurrentlyUploading 
    opacity: enabled ? 1.0 : 0.4

    onClicked: {
      let dashboard = iface.findItemByObjectName("dashBoard")
      if (dashboard) dashboard.close()
      plugin.loadCredentialsFromJSON()
      plugin.triggerManualUpload() 
    }
    onPressAndHold: configure()
  }

  QfDialog {
    id: settingsDialog; parent: mainWindow.contentItem; modal: true
    title: qsTr("Nextcloud WebDAV Configuration (Native)")
    standardButtons: Dialog.Ok | Dialog.Cancel
    width: Math.min(parent.width - 40, 480)
    x: (parent.width - width) / 2; y: (parent.height - height) / 2

    onOpened: {
      enableSwitch.checked = appSettings.autoUploadEnabled
      intervalTumbler.currentIndex = Math.max(0, appSettings.intervalHours - 1)
      plugin.loadCredentialsFromJSON()
      urlField.text = plugin.storedUrl
      userField.text = plugin.storedUser
      passField.text = plugin.storedPass
      structureField.text = plugin.storedStructure
      plugin.testStatusText = ""
    }

    onAccepted: {
      appSettings.autoUploadEnabled = enableSwitch.checked
      appSettings.intervalHours = intervalTumbler.currentIndex + 1
      plugin.saveCredentialsToJSON() 
      plugin.loadCredentialsFromJSON() 
      uploadTimer.running = appSettings.autoUploadEnabled
    }

    ColumnLayout {
      width: parent.width; spacing: 12
      
      ColumnLayout {
        Layout.fillWidth: true; spacing: 4
        Label { text: qsTr("System Log:"); font: Theme.tipFont; color: Theme.secondaryTextColor }
        ScrollView {
          Layout.fillWidth: true; Layout.preferredHeight: 120; clip: true
          TextArea {
            id: copyableLogText; text: plugin.initLogBuffer; font.family: "Courier"; font.pointSize: 9
            readOnly: false; activeFocusOnPress: true; selectByMouse: true; selectByKeyboard: true
            color: Theme.mainTextColor; wrapMode: TextArea.Wrap
            background: Rectangle { color: "transparent"; border.color: Theme.controlBorderColor; radius: 4 }
            onTextChanged: { cursorPosition = text.length }
          }
        }
      }

      Rectangle { Layout.fillWidth: true; height: 1; color: Theme.controlBorderColor }

      ColumnLayout {
        Layout.fillWidth: true; spacing: 6
        Label { text: qsTr("Nextcloud Connection"); font: Theme.defaultFont; color: Theme.mainTextColor }
        TextField { id: urlField; Layout.fillWidth: true; placeholderText: "https://cloud.de"; font: Theme.defaultFont; color: Theme.mainTextColor; background: Rectangle { border.color: Theme.controlBorderColor; radius: 4; color: "transparent" } }
        RowLayout {
          Layout.fillWidth: true; spacing: 8
          TextField { id: userField; Layout.fillWidth: true; placeholderText: qsTr("Username"); font: Theme.defaultFont; color: Theme.mainTextColor; background: Rectangle { border.color: Theme.controlBorderColor; radius: 4; color: "transparent" } }
          TextField { id: passField; Layout.fillWidth: true; placeholderText: qsTr("App Password"); echoMode: TextInput.Password; font: Theme.defaultFont; color: Theme.mainTextColor; background: Rectangle { border.color: Theme.controlBorderColor; radius: 4; color: "transparent" } }
        }
        Label { text: qsTr("Target structure in the Cloud"); font: Theme.tipFont; color: Theme.secondaryTextColor; Layout.topMargin: 2 }
        TextField { id: structureField; Layout.fillWidth: true; placeholderText: "e.g. /Steinheim/Qfield/"; font: Theme.defaultFont; color: Theme.mainTextColor; background: Rectangle { border.color: Theme.controlBorderColor; radius: 4; color: "transparent" } }
        
        RowLayout {
          Layout.fillWidth: true; Layout.topMargin: 4; spacing: 10
          Button {
            text: qsTr("Test connection")
            onClicked: plugin.testNextcloudConnection(urlField.text, userField.text, passField.text, structureField.text)
          }
          Label {
            text: plugin.testStatusText
            color: plugin.testStatusColor
            font: Theme.tipFont
            Layout.fillWidth: true; wrapMode: Text.WordWrap
          }
        }
      }

      Rectangle { Layout.fillWidth: true; height: 1; color: Theme.controlBorderColor }

      RowLayout {
        Layout.fillWidth: true; spacing: 12
        ColumnLayout {
          Layout.fillWidth: true; spacing: 4
          Label { text: qsTr("Enable auto-upload"); font: Theme.defaultFont; color: Theme.mainTextColor }
          Label { text: qsTr("Automatically sync WebDAV projects at regular intervals"); font: Theme.tipFont; color: Theme.secondaryTextColor; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
        Switch { id: enableSwitch }
      }

      Rectangle { Layout.fillWidth: true; height: 1; color: Theme.controlBorderColor }

      RowLayout {
        Layout.fillWidth: true; spacing: 16; opacity: enableSwitch.checked ? 1.0 : 0.4
        Label { text: qsTr("Upload interval"); font: Theme.defaultFont; color: Theme.mainTextColor }
        Item {
          Layout.preferredWidth: 60; Layout.preferredHeight: 60
          Tumbler {
            id: intervalTumbler; anchors.fill: parent; model: 24; wrap: true; visibleItemCount: 3; enabled: enableSwitch.checked
            delegate: Label { text: modelData + 1; font: Theme.defaultFont; color: Theme.mainTextColor; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
          }
          Rectangle { anchors.centerIn: parent; width: parent.width + 8; height: 24; color: "transparent"; border.color: enableSwitch.checked ? Theme.mainColor : Theme.controlBorderColor; radius: 4 }
        }
        Label { text: (intervalTumbler.currentIndex + 1) === 1 ? qsTr("hour") : qsTr("hours"); font: Theme.defaultFont; color: Theme.mainTextColor }
        Item { Layout.fillWidth: true }
      }
    }
  }
}
