// Copyright H. Striepe - 2025
// Code inspiration - copyright Simon Guest - 2025

import AVFoundation
import AVKit
import Cocoa
import CoreAudio

// MARK: - QCAppDelegate Class
@NSApplicationMain
class QCAppDelegate: NSObject, NSApplicationDelegate, QCUsbWatcherDelegate, QCCaptureManagerDelegate, QCAudioManagerDelegate, QCWindowManagerDelegate, QCCaptureFileManagerDelegate, QCNotificationManagerDelegate, QCDisplaySleepManagerDelegate, QCPreferencesControllerDelegate {

    // MARK: - Managers
    private var captureManager: QCCaptureManager!
    private var audioManager: QCAudioManager!
    private var windowManager: QCWindowManager!
    private var fileManager: QCCaptureFileManager!
    private var notificationManager: QCNotificationManager!
    private var displaySleepManager: QCDisplaySleepManager!
    private var preferencesController: QCPreferencesController!

    // MARK: - USB Watcher
    let usb: QCUsbWatcher = QCUsbWatcher()
    func deviceCountChanged() {
        captureManager.detectVideoDevices()
        captureManager.startCaptureWithVideoDevice(deviceIndex: captureManager.selectedDeviceIndex)
        audioManager.detectAudioDevices()
    }

    // MARK: - Interface Builder Outlets
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var selectSourceMenu: NSMenuItem!
    @IBOutlet weak var selectAudioSourceMenu: NSMenuItem!
    @IBOutlet weak var selectAudioOutputMenu: NSMenuItem!
    @IBOutlet weak var muteAudioMenuItem: NSMenuItem!
    @IBOutlet weak var volumeMenu: NSMenuItem!
    @IBOutlet weak var borderlessMenu: NSMenuItem!
    @IBOutlet weak var aspectRatioFixedMenu: NSMenuItem!
    @IBOutlet weak var mirroredMenu: NSMenuItem!
    @IBOutlet weak var upsideDownMenu: NSMenuItem!
    @IBOutlet weak var playerView: NSView!
    @IBOutlet weak var displaySleepMenuItem: NSMenuItem!
    @IBOutlet weak var captureVideoMenuItem: NSMenuItem!

    // MARK: - Settings Properties (delegated to window manager)
    var isMirrored: Bool {
        get { windowManager?.isMirrored ?? QCSettingsManager.shared.isMirrored }
        set { windowManager?.isMirrored = newValue }
    }
    var isUpsideDown: Bool {
        get { windowManager?.isUpsideDown ?? QCSettingsManager.shared.isUpsideDown }
        set { windowManager?.isUpsideDown = newValue }
    }
    var position: Int {
        get { windowManager?.position ?? QCSettingsManager.shared.position }
        set { windowManager?.position = newValue }
    }
    var isBorderless: Bool {
        get { windowManager?.isBorderless ?? QCSettingsManager.shared.isBorderless }
        set { windowManager?.isBorderless = newValue }
    }
    var isAspectRatioFixed: Bool {
        get { windowManager?.isAspectRatioFixed ?? QCSettingsManager.shared.isAspectRatioFixed }
        set { windowManager?.isAspectRatioFixed = newValue }
    }
    var deviceName: String {
        get { QCSettingsManager.shared.deviceName }
        set { QCSettingsManager.shared.setDeviceName(newValue) }
    }

    // MARK: - Window Properties
    let defaultDeviceIndex: Int = 0
    var selectedDeviceIndex: Int {
        get { captureManager?.selectedDeviceIndex ?? 0 }
        set { /* managed by captureManager */ }
    }

    var savedDeviceName: String = "-"
    
    // Computed properties for backward compatibility
    var windowTitle: String {
        get { windowManager?.windowTitle ?? "CapturePlay" }
        set { windowManager?.setWindowTitle(newValue) }
    }
    
    // Computed properties for backward compatibility
    var devices: [AVCaptureDevice] {
        captureManager?.devices ?? []
    }
    var captureSession: AVCaptureSession? {
        captureManager?.captureSession
    }
    var captureLayer: AVCaptureVideoPreviewLayer? {
        captureManager?.getPreviewLayer()
    }
    var input: AVCaptureDeviceInput? {
        captureManager?.getInput()
    }
    // Computed properties for backward compatibility
    private var audioCaptureInput: AVCaptureDeviceInput? {
        audioManager?.getAudioCaptureInput()
    }
    private var audioPreviewOutput: AVCaptureAudioPreviewOutput? {
        audioManager?.getAudioPreviewOutput()
    }
    private var isRecording: Bool {
        captureManager?.isRecording ?? false
    }
    private var volumeSlider: NSSlider?
    
    // Computed property for backward compatibility
    private var isFullScreenActive: Bool {
        windowManager?.isFullScreenActive ?? false
    }

    // MARK: - Error Handling
    func errorMessage(message: String) {
        let popup: NSAlert = NSAlert()
        popup.messageText = message
        popup.runModal()
    }

    // MARK: - Device Management
    func detectVideoDevices() {
        captureManager.detectVideoDevices()
    }
    
    private func buildDeviceMenu(devices: [AVCaptureDevice], currentDeviceIndex: Int) {
        let deviceMenu: NSMenu = NSMenu()
        var deviceIndex: Int = 0

        for device: AVCaptureDevice in devices {
            let deviceMenuItem: NSMenuItem = NSMenuItem(
                title: device.localizedName, action: #selector(deviceMenuChanged), keyEquivalent: ""
            )
            deviceMenuItem.target = self
            deviceMenuItem.representedObject = deviceIndex
            if deviceIndex == currentDeviceIndex {
                deviceMenuItem.state = NSControl.StateValue.on
            }
            if deviceIndex < 9 {
                deviceMenuItem.keyEquivalent = String(deviceIndex + 1)
            }
            deviceMenu.addItem(deviceMenuItem)
            deviceIndex += 1
        }
        selectSourceMenu.submenu = deviceMenu
    }

    // MARK: - Settings Management
    func logSettings(label: String) {
        QCSettingsManager.shared.logSettings(label: label)
    }

    func loadSettings() {
        QCSettingsManager.shared.loadSettings()
    }

    func applySettings() {
        QCSettingsManager.shared.logSettings(label: "applySettings")

        guard let windowManager = windowManager else { return }
        windowManager.setRotation(windowManager.position)
        windowManager.applyMirroring()
        windowManager.fixAspectRatio()

        self.borderlessMenu.state = convertToNSControlStateValue(
            (windowManager.isBorderless ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        self.mirroredMenu.state = convertToNSControlStateValue(
            (windowManager.isMirrored ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        self.upsideDownMenu.state = convertToNSControlStateValue(
            (windowManager.isUpsideDown ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        self.aspectRatioFixedMenu.state = convertToNSControlStateValue(
            (windowManager.isAspectRatioFixed
                ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }

    // MARK: - Settings Actions
    @IBAction func saveSettings(_ sender: NSMenuItem) {
        QCSettingsManager.shared.setFrameProperties(
            x: Float(self.window.frame.minX),
            y: Float(self.window.frame.minY),
            width: Float(self.window.frame.width),
            height: Float(self.window.frame.height)
        )
        QCSettingsManager.shared.saveSettings()
    }

    @IBAction func clearSettings(_ sender: NSMenuItem) {
        QCSettingsManager.shared.clearSettings()
        displaySleepManager.applyDisplaySleepPreferenceFromSettings(force: true)
        audioManager.detectAudioDevices()
    }

    // MARK: - Display Actions
    @IBAction func mirrorHorizontally(_ sender: NSMenuItem) {
        NSLog("Mirror image menu item selected")
        windowManager.toggleMirrorHorizontally()
    }

    @IBAction func mirrorVertically(_ sender: NSMenuItem) {
        NSLog("Mirror image vertically menu item selected")
        windowManager.toggleMirrorVertically()
    }

    @IBAction func rotateLeft(_ sender: NSMenuItem) {
        NSLog("Rotate Left menu item selected with position %d", position)
        windowManager.rotateLeft()
    }

    @IBAction func rotateRight(_ sender: NSMenuItem) {
        NSLog("Rotate Right menu item selected with position %d", position)
        windowManager.rotateRight()
    }

    @IBAction func borderless(_ sender: NSMenuItem) {
        NSLog("Borderless menu item selected")
        windowManager.toggleBorderless()
        sender.state = convertToNSControlStateValue(
            (isBorderless ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }

    @IBAction func enterFullScreen(_ sender: NSMenuItem) {
        NSLog("Enter full screen menu item selected")
        windowManager.enterFullScreen()
    }

    @IBAction func toggleFixAspectRatio(_ sender: NSMenuItem) {
        windowManager.toggleFixAspectRatio()
        sender.state = convertToNSControlStateValue(
            (isAspectRatioFixed
                ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }

    @IBAction func fitToActualSize(_ sender: NSMenuItem) {
        windowManager.fitToActualSize()
    }

    @IBAction func saveImage(_ sender: NSMenuItem) {
        fileManager.saveImage()
    }

    @IBAction func captureImage(_ sender: NSMenuItem) {
        fileManager.captureImage()
    }

    @IBAction func captureVideo(_ sender: NSMenuItem) {
        guard let captureDir = fileManager.getCaptureDirectory() else {
            errorMessage(message: "Unable to access the capture directory.\n\nPlease check your settings.")
            return
        }
        captureManager.toggleRecording(captureDirectory: captureDir)
    }
    
    @IBAction func openCaptureFolder(_ sender: NSMenuItem) {
        fileManager.openCaptureFolder()
    }
    

    // MARK: - Device Menu Actions
    @objc func deviceMenuChanged(_ sender: NSMenuItem) {
        NSLog("Device Menu changed")
        if sender.state == NSControl.StateValue.on {
            // selected the active device, so nothing to do here
            return
        }

        // set the checkbox on the currently selected device
        for menuItem: NSMenuItem in selectSourceMenu.submenu!.items {
            menuItem.state = NSControl.StateValue.off
        }
        sender.state = NSControl.StateValue.on

        let deviceIndex = sender.representedObject as! Int
        captureManager.startCaptureWithVideoDevice(deviceIndex: deviceIndex)
    }

    // MARK: - Application Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Initialize window manager
        windowManager = QCWindowManager()
        windowManager.delegate = self
        windowManager.window = window
        windowManager.playerView = playerView
        
        // Initialize capture manager
        captureManager = QCCaptureManager()
        captureManager.delegate = self
        captureManager.previewView = playerView
        
        // Initialize audio manager (will be connected to session after capture starts)
        audioManager = QCAudioManager(captureSession: nil)
        audioManager.delegate = self
        
        // Initialize file manager
        fileManager = QCCaptureFileManager()
        fileManager.delegate = self
        fileManager.window = window
        fileManager.windowManager = windowManager
        
        // Initialize notification manager
        notificationManager = QCNotificationManager()
        notificationManager.delegate = self
        
        // Initialize display sleep manager
        displaySleepManager = QCDisplaySleepManager()
        displaySleepManager.delegate = self
        displaySleepManager.isFullScreenActive = windowManager.isFullScreenActive
        
        // Initialize preferences controller
        preferencesController = QCPreferencesController(parentWindow: window)
        preferencesController.delegate = self
        
        // Load settings first (needed for device detection)
        self.loadSettings()
        displaySleepManager.applyDisplaySleepPreferenceFromSettings()
        
        // Load window frame from settings
        windowManager.loadWindowFrame()
        
        // Apply borderless setting if needed
        if isBorderless {
            windowManager.removeBorder()
        }
        
        detectVideoDevices()
        captureManager.startCaptureWithVideoDevice(deviceIndex: defaultDeviceIndex)
        usb.delegate = self
        setupFileMenu()
        displaySleepManager.applyDisplaySleepPreferenceFromSettings(force: true)
        windowManager.observeWindowNotifications()
        requestAudioAccessIfNeeded()
        setupVolumeSlider()
        updateCaptureVideoMenuItemState()
        notificationManager.requestNotificationPermissions()
        
        // Connect file manager to capture session/layer after capture starts
        fileManager.captureSession = captureManager.captureSession
        fileManager.captureLayer = captureManager.getPreviewLayer()
    }

    // MARK: - Menu Setup
    private func ensureFileMenu() -> NSMenu? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        if let item = mainMenu.item(withTitle: "File") {
            return item.submenu
        }
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileSubmenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileSubmenu
        let insertIndex = mainMenu.items.count > 0 ? 1 : 0
        mainMenu.insertItem(fileMenuItem, at: insertIndex)
        return fileSubmenu
    }

    private func findMenuItem(in menu: NSMenu, where predicate: (NSMenuItem) -> Bool) -> (NSMenuItem, NSMenu)? {
        for item in menu.items {
            if predicate(item) {
                return (item, menu)
            }
            if let submenu = item.submenu, let found = findMenuItem(in: submenu, where: predicate) {
                return found
            }
        }
        return nil
    }

    private func collectMenuItems(in menu: NSMenu, where predicate: (NSMenuItem) -> Bool, into result: inout [(NSMenuItem, NSMenu)]) {
        for item in menu.items {
            if predicate(item) {
                result.append((item, menu))
            }
            if let submenu = item.submenu {
                collectMenuItems(in: submenu, where: predicate, into: &result)
            }
        }
    }

    private func moveFirstMenuItem(withAction action: Selector, to destination: NSMenu) -> Bool {
        guard let mainMenu = NSApp.mainMenu else { return false }
        if let found = findMenuItem(in: mainMenu, where: { $0.action == action }) {
            let (item, parent) = found
            parent.removeItem(item)
            destination.addItem(item)
            return true
        }
        return false
    }

    private func removeCloseAllMenuItem(from menu: NSMenu) {
        let selectors: [Selector] = [
            NSSelectorFromString("closeAllDocuments:"),
            NSSelectorFromString("closeAll:")
        ]
        if let item = menu.items.first(where: { $0.title == "Close All" || ( $0.action != nil && selectors.contains($0.action!) ) }) {
            menu.removeItem(item)
        }
    }

    private func setupFileMenu() {
        guard let fileMenu = ensureFileMenu() else { return }

        var addedAny = false

        // Move Save Settings
        if moveFirstMenuItem(withAction: #selector(saveSettings(_:)), to: fileMenu) {
            addedAny = true
        }

        // Move Clear Settings
        if moveFirstMenuItem(withAction: #selector(clearSettings(_:)), to: fileMenu) {
            addedAny = true
        }

        // Move any items with titles containing "ruler"
        if let mainMenu = NSApp.mainMenu {
            var rulerItems: [(NSMenuItem, NSMenu)] = []
            collectMenuItems(in: mainMenu, where: { $0.title.localizedCaseInsensitiveContains("ruler") }, into: &rulerItems)
            if !rulerItems.isEmpty {
                if addedAny {
                    fileMenu.addItem(NSMenuItem.separator())
                }
                for (item, parent) in rulerItems {
                    parent.removeItem(item)
                    fileMenu.addItem(item)
                }
                addedAny = true
            }
        }

        // Move Close (performClose:)
        if let mainMenu = NSApp.mainMenu {
            if let (closeItem, parent) = findMenuItem(in: mainMenu, where: { $0.action == #selector(NSWindow.performClose(_:)) || $0.title == "Close" }) {
                parent.removeItem(closeItem)
                if addedAny {
                    fileMenu.addItem(NSMenuItem.separator())
                }
                fileMenu.addItem(closeItem)
            } else {
                // If no existing Close item was found, create one
                if addedAny {
                    fileMenu.addItem(NSMenuItem.separator())
                }
                let closeItem = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
                closeItem.keyEquivalentModifierMask = [.command]
                closeItem.target = nil // use responder chain
                fileMenu.addItem(closeItem)
            }
        }

        removeCloseAllMenuItem(from: fileMenu)
    }

    // MARK: - Audio Management
    private func detectAudioDevices() {
        audioManager.detectAudioDevices()
    }

    private func setupVolumeSlider() {
        guard let volumeMenuItem = volumeMenu else { return }
        
        // Skip if already set up
        if volumeMenuItem.view != nil {
            return
        }
        
        // Create container view
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 22))
        
        // Create label
        let label = NSTextField(labelWithString: "Volume:")
        label.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        label.frame = NSRect(x: 8, y: 2, width: 50, height: 18)
        containerView.addSubview(label)
        
        // Create slider
        let slider = NSSlider(frame: NSRect(x: 60, y: 4, width: 110, height: 16))
        slider.minValue = 0.0
        slider.maxValue = 1.0
        slider.doubleValue = Double(QCSettingsManager.shared.audioVolume)
        slider.target = self
        slider.action = #selector(volumeSliderChanged(_:))
        slider.isContinuous = true
        containerView.addSubview(slider)
        
        volumeSlider = slider
        volumeMenuItem.view = containerView
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        let volume = Float(sender.doubleValue)
        audioManager.setVolume(volume)
        QCSettingsManager.shared.saveSettings()
    }

    private func updateVolumeSlider() {
        volumeSlider?.doubleValue = Double(QCSettingsManager.shared.audioVolume)
    }

    private func requestAudioAccessIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized, .restricted, .denied:
            // Don't detect devices here - wait for capture session to be set
            // Devices will be detected in didChangeDevice delegate method
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    // Devices will be detected when session is set
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func audioInputMenuChanged(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        audioManager.setAudioInput(uid: uid)
    }

    @objc private func audioOutputMenuChanged(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        audioManager.setAudioOutput(uid: uid)
    }

    @IBAction func toggleAudioMute(_ sender: NSMenuItem) {
        audioManager.toggleMute()
    }

    private func updateCaptureVideoMenuItemState() {
        captureVideoMenuItem?.state = isRecording ? .on : .off
    }

    @IBAction func toggleDisplaySleep(_ sender: NSMenuItem) {
        displaySleepManager.toggleDisplaySleep()
    }

    @IBAction func showPreferences(_ sender: NSMenuItem) {
        preferencesController.showPreferences()
    }

    // Help viewer instance
    private var helpViewer: QCHelpViewerController?
    
    // Handle the standard help action - show HTML manual in WebView
    @IBAction func showHelp(_ sender: Any?) {
        print("QCAppDelegate: showHelp called")
        
        // Show HTML help in WebView
        if let existingViewer = helpViewer, let window = existingViewer.window, window.isVisible {
            window.makeKeyAndOrderFront(sender)
            print("QCAppDelegate: Showing existing help window")
        } else {
            print("QCAppDelegate: Creating new help viewer")
            let viewer = QCHelpViewerController()
            viewer.delegate = self
            helpViewer = viewer
            viewer.showWindow(sender)
            print("QCAppDelegate: showWindow called")
        }
    }
    
    @IBAction func showUserManual(_ sender: Any?) {
        // Open MANUAL.pdf from Resources
        var pdfURL: URL?
        
        // First try: MANUAL.pdf in bundle Resources
        if let manualURL = Bundle.main.url(forResource: "MANUAL", withExtension: "pdf") {
            pdfURL = manualURL
        }
        // Second try: Check Resources directory directly
        else if let resourcesPath = Bundle.main.resourcePath {
            let pdfPath = (resourcesPath as NSString).appendingPathComponent("MANUAL.pdf")
            if FileManager.default.fileExists(atPath: pdfPath) {
                pdfURL = URL(fileURLWithPath: pdfPath)
            }
        }
        // Third try: Source directory (for development)
        else {
            let bundlePath = Bundle.main.bundlePath as NSString
            var path = bundlePath.deletingLastPathComponent // Contents
            path = (path as NSString).deletingLastPathComponent // .app
            path = (path as NSString).deletingLastPathComponent // Source directory
            var pdfPath = (path as NSString).appendingPathComponent("captureplay/Resources/MANUAL.pdf")
            
            if !FileManager.default.fileExists(atPath: pdfPath) {
                pdfPath = (path as NSString).appendingPathComponent("captureplay/MANUAL.pdf")
            }
            
            if FileManager.default.fileExists(atPath: pdfPath) {
                pdfURL = URL(fileURLWithPath: pdfPath)
            }
        }
        
        if let url = pdfURL {
            NSWorkspace.shared.open(url)
        } else {
            let alert = NSAlert()
            alert.messageText = "Manual Not Found"
            alert.informativeText = "The MANUAL.pdf file could not be found in the application bundle Resources folder."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    

    func applicationWillTerminate(_ notification: Notification) {
        displaySleepManager?.cleanup()
        windowManager?.updateWindowFrameSettings()
        QCSettingsManager.shared.saveSettings()
    }


    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - QCCaptureManagerDelegate
extension QCAppDelegate {
    func captureManager(_ manager: QCCaptureManager, didDetectDevices devices: [AVCaptureDevice]) {
        // Build device menu
        let currentDeviceIndex: Int
        if captureSession != nil, let currentInput = input {
            let currentDevice = currentInput.device
            currentDeviceIndex = devices.firstIndex(of: currentDevice) ?? defaultDeviceIndex
        } else {
            currentDeviceIndex = defaultDeviceIndex
        }
        buildDeviceMenu(devices: devices, currentDeviceIndex: currentDeviceIndex)
    }
    
    func captureManager(_ manager: QCCaptureManager, didChangeDevice device: AVCaptureDevice, deviceIndex: Int) {
        // Update device menu selection
        if let menu = selectSourceMenu.submenu {
            for (index, item) in menu.items.enumerated() {
                item.state = (index == deviceIndex) ? .on : .off
            }
        }
        // Connect audio manager to capture session and detect devices
        if let session = captureManager.captureSession {
            audioManager.captureSession = session
            // Detect audio devices now that we have a session
            audioManager.detectAudioDevices()
        }
        // Connect window manager to capture layer and input
        windowManager.captureLayer = captureManager.getPreviewLayer()
        windowManager.videoInput = captureManager.getInput()
        
        // Connect file manager to capture session and layer
        fileManager.captureSession = captureManager.captureSession
        fileManager.captureLayer = captureManager.getPreviewLayer()
    }
    
    func captureManager(_ manager: QCCaptureManager, didStartRecordingTo url: URL) {
        updateCaptureVideoMenuItemState()
        let filename = url.lastPathComponent
        notificationManager.sendNotification(title: "Video Recording", body: "Recording started: \(filename)", sound: true)
    }
    
    func captureManager(_ manager: QCCaptureManager, didFinishRecordingTo url: URL, error: Error?) {
        updateCaptureVideoMenuItemState()
        if error == nil {
            let filename = url.lastPathComponent
            notificationManager.sendNotification(title: "Video Recording", body: "Recording saved: \(filename)", sound: true)
        }
    }
    
    func captureManager(_ manager: QCCaptureManager, didEncounterError error: Error, message: String) {
        errorMessage(message: message)
    }
    
    func captureManager(_ manager: QCCaptureManager, needsAudioDeviceUpdateFor videoDevice: AVCaptureDevice) {
        audioManager.updatePreferredInputFromVideo(videoDevice: videoDevice)
        // detectAudioDevices will be called in didChangeDevice, but we can also call it here
        // to ensure devices are refreshed after video device change
        if audioManager.captureSession != nil {
            audioManager.detectAudioDevices()
        }
    }
    
    func captureManager(_ manager: QCCaptureManager, needsSettingsApplication: Void) {
        applySettings()
    }
    
    func captureManager(_ manager: QCCaptureManager, needsWindowTitleUpdate title: String) {
        windowManager.setWindowTitle(title)
    }
    
    func captureManager(_ manager: QCCaptureManager, needsDeviceNameUpdate name: String) {
        deviceName = name
    }
    
    func captureManager(_ manager: QCCaptureManager, didChangeRecordingState isRecording: Bool) {
        updateCaptureVideoMenuItemState()
    }
}

// MARK: - QCAudioManagerDelegate
extension QCAppDelegate {
    func audioManager(_ manager: QCAudioManager, didDetectInputDevices devices: [AVCaptureDevice]) {
        // Devices detected, menus will be updated via needsMenuUpdateForInput
    }
    
    func audioManager(_ manager: QCAudioManager, didDetectOutputDevices devices: [AudioOutputDeviceInfo]) {
        // Devices detected, menus will be updated via needsMenuUpdateForOutput
    }
    
    func audioManager(_ manager: QCAudioManager, didChangeInput device: AVCaptureDevice?) {
        // Input changed, update capture manager reference
        captureManager.audioCaptureInput = manager.getAudioCaptureInput()
    }
    
    func audioManager(_ manager: QCAudioManager, didChangeOutput deviceUID: String?) {
        // Output changed
    }
    
    func audioManager(_ manager: QCAudioManager, needsMenuUpdateForInput devices: [AVCaptureDevice], selectedUID: String?) {
        let menu = NSMenu()
        if devices.isEmpty {
            let item = NSMenuItem(
                title: "No Audio Inputs Available",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
            selectAudioSourceMenu.isEnabled = false
        } else {
            selectAudioSourceMenu.isEnabled = true
            for device in devices {
                let item = NSMenuItem(
                    title: device.localizedName,
                    action: #selector(audioInputMenuChanged),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device.uniqueID
                item.state = (device.uniqueID == selectedUID) ? .on : .off
                menu.addItem(item)
            }
        }
        selectAudioSourceMenu.submenu = menu
    }
    
    func audioManager(_ manager: QCAudioManager, needsMenuUpdateForOutput devices: [AudioOutputDeviceInfo], selectedUID: String?) {
        let menu = NSMenu()
        if devices.isEmpty {
            let item = NSMenuItem(
                title: "No Audio Outputs Available",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
            selectAudioOutputMenu.isEnabled = false
        } else {
            selectAudioOutputMenu.isEnabled = true
            for device in devices {
                let item = NSMenuItem(
                    title: device.name,
                    action: #selector(audioOutputMenuChanged),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device.uid
                item.state = (device.uid == selectedUID) ? .on : .off
                menu.addItem(item)
            }
        }
        selectAudioOutputMenu.submenu = menu
    }
    
    func audioManager(_ manager: QCAudioManager, didChangeMuteState muted: Bool) {
        muteAudioMenuItem?.state = muted ? .on : .off
    }
    
    func audioManager(_ manager: QCAudioManager, didChangeVolume volume: Float) {
        updateVolumeSlider()
    }
}

// MARK: - QCWindowManagerDelegate
extension QCAppDelegate {
    func windowManager(_ manager: QCWindowManager, willEnterFullScreen: Bool) {
        displaySleepManager.isFullScreenActive = manager.isFullScreenActive
        displaySleepManager.handleWillEnterFullScreen()
    }

    func windowManager(_ manager: QCWindowManager, didEnterFullScreen: Bool) {
        displaySleepManager.isFullScreenActive = manager.isFullScreenActive
    }
    
    func windowManager(_ manager: QCWindowManager, willExitFullScreen: Bool) {
        displaySleepManager.handleWillExitFullScreen()
    }

    func windowManager(_ manager: QCWindowManager, didExitFullScreen: Bool) {
        displaySleepManager.isFullScreenActive = manager.isFullScreenActive
        displaySleepManager.handleDidExitFullScreen()
        windowManager.updateWindowFrameSettings()
    }
    
    func windowManager(_ manager: QCWindowManager, didChangeFrame frame: NSRect) {
        // Frame changed, settings will be updated automatically via notifications
    }
    
    func windowManager(_ manager: QCWindowManager, needsSettingsUpdate: Void) {
        applySettings()
    }
    
    func windowManager(_ manager: QCWindowManager, didChangeBorderless isBorderless: Bool) {
        borderlessMenu.state = convertToNSControlStateValue(
            (isBorderless ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }
    
    func windowManager(_ manager: QCWindowManager, didChangeRotation position: Int) {
        // Rotation changed, settings applied via needsSettingsUpdate
    }
    
    func windowManager(_ manager: QCWindowManager, didChangeMirroring isMirrored: Bool) {
        mirroredMenu.state = convertToNSControlStateValue(
            (isMirrored ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }
    
    func windowManager(_ manager: QCWindowManager, didChangeUpsideDown isUpsideDown: Bool) {
        upsideDownMenu.state = convertToNSControlStateValue(
            (isUpsideDown ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }
    
    func windowManager(_ manager: QCWindowManager, didChangeAspectRatioFixed isFixed: Bool) {
        aspectRatioFixedMenu.state = convertToNSControlStateValue(
            (isFixed ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }
}

// MARK: - QCCaptureFileManagerDelegate
extension QCAppDelegate {
    func captureFileManager(_ manager: QCCaptureFileManager, didSaveImageTo url: URL, filename: String) {
        NSLog("Image saved to: %@", url.path)
    }
    
    func captureFileManager(_ manager: QCCaptureFileManager, didEncounterError error: Error, message: String) {
        errorMessage(message: message)
    }
    
    func captureFileManager(_ manager: QCCaptureFileManager, needsNotification title: String, body: String, sound: Bool) {
        notificationManager.sendNotification(title: title, body: body, sound: sound)
    }
}

// MARK: - QCNotificationManagerDelegate
extension QCAppDelegate {
    func notificationManager(_ manager: QCNotificationManager, didRequestPermissions granted: Bool, error: Error?) {
        // Permissions requested, can handle if needed
    }
    
    func notificationManager(_ manager: QCNotificationManager, didSendNotification title: String, body: String, error: Error?) {
        // Notification sent, can handle if needed
    }
}

// MARK: - QCDisplaySleepManagerDelegate
extension QCAppDelegate {
    func displaySleepManager(_ manager: QCDisplaySleepManager, didChangeState isPreventing: Bool) {
        // State changed, can handle if needed
    }
    
    func displaySleepManager(_ manager: QCDisplaySleepManager, needsNotification title: String, body: String, sound: Bool) {
        notificationManager.sendNotification(title: title, body: body, sound: sound)
    }
    
    func displaySleepManager(_ manager: QCDisplaySleepManager, needsErrorDisplay message: String) {
        errorMessage(message: message)
    }
    
    func displaySleepManager(_ manager: QCDisplaySleepManager, needsMenuItemUpdate isPreventing: Bool) {
        displaySleepMenuItem?.state = isPreventing ? .off : .on
    }
    
    func displaySleepManager(_ manager: QCDisplaySleepManager, needsMenuItemEnabled enabled: Bool) {
        displaySleepMenuItem?.isEnabled = enabled
    }
}

// MARK: - QCHelpViewerDelegate
extension QCAppDelegate: QCHelpViewerDelegate {
    func helpViewerDidClose(_ helpViewer: QCHelpViewerController) {
        // Help viewer was closed, clear reference
        if self.helpViewer === helpViewer {
            self.helpViewer = nil
        }
    }
}

// MARK: - QCPreferencesControllerDelegate
extension QCAppDelegate {
    func preferencesController(_ controller: QCPreferencesController, didSavePreferences: Void) {
        // Preferences saved, can handle if needed (e.g., refresh settings)
    }
}

// MARK: - Helper Functions
// Helper function inserted by Swift 4.2 migrator.
private func convertToNSControlStateValue(_ input: Int) -> NSControl.StateValue {
    NSControl.StateValue(rawValue: input)
}

// Helper function inserted by Swift 4.2 migrator.
private func convertToNSWindowLevel(_ input: Int) -> NSWindow.Level {
    NSWindow.Level(rawValue: input)
}

