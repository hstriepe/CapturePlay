// Copyright H. Striepe ©2025
// Inspired by Quick-Camera - Simon Guest ©2025

import AVFoundation
import AVKit
import Cocoa
import CoreAudio

// MARK: - CPAppDelegate Class
@NSApplicationMain
class CPAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, CPUsbWatcherDelegate, CPCaptureManagerDelegate, CPAudioManagerDelegate, CPWindowManagerDelegate, CPCaptureFileManagerDelegate, CPNotificationManagerDelegate, CPDisplaySleepManagerDelegate, CPPreferencesControllerDelegate, CPColorCorrectionControllerDelegate {

    // MARK: - Managers
    private var captureManager: CPCaptureManager!
    private var audioManager: CPAudioManager!
    private var windowManager: CPWindowManager!
    private var fileManager: CPCaptureFileManager!
    private var notificationManager: CPNotificationManager!
    private var displaySleepManager: CPDisplaySleepManager!
    private var preferencesController: CPPreferencesController!
    private var colorCorrectionController: CPColorCorrectionController?

    // MARK: - USB Watcher
    let usb: CPUsbWatcher = CPUsbWatcher()
    func deviceCountChanged() {
        captureManager.detectVideoDevices()
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
    @IBOutlet weak var imageMenu: NSMenuItem!

    // MARK: - Test Environment Detection
    private var isRunningInTests: Bool {
        // Check multiple ways to detect test environment
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
               ProcessInfo.processInfo.arguments.contains("-XCTest") ||
               NSClassFromString("XCTestCase") != nil
    }
    
    // MARK: - Settings Properties (delegated to window manager)
    var isMirrored: Bool {
        get { windowManager?.isMirrored ?? CPSettingsManager.shared.isMirrored }
        set { windowManager?.isMirrored = newValue }
    }
    var isUpsideDown: Bool {
        get { windowManager?.isUpsideDown ?? CPSettingsManager.shared.isUpsideDown }
        set { windowManager?.isUpsideDown = newValue }
    }
    var position: Int {
        get { windowManager?.position ?? CPSettingsManager.shared.position }
        set { windowManager?.position = newValue }
    }
    var isBorderless: Bool {
        get { windowManager?.isBorderless ?? CPSettingsManager.shared.isBorderless }
        set { windowManager?.isBorderless = newValue }
    }
    var isAspectRatioFixed: Bool {
        get { windowManager?.isAspectRatioFixed ?? CPSettingsManager.shared.isAspectRatioFixed }
        set { windowManager?.isAspectRatioFixed = newValue }
    }
    var deviceName: String {
        get { CPSettingsManager.shared.deviceName }
        set { CPSettingsManager.shared.setDeviceName(newValue) }
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
        NSLog("Building device menu with %d devices, currentDeviceIndex: %d", devices.count, currentDeviceIndex)
        
        DispatchQueue.main.async {
            // Create a completely new menu to avoid XIB conflicts
            let deviceMenu = NSMenu(title: "Select Source")
            deviceMenu.autoenablesItems = true
            
            var deviceIndex: Int = 0
            for device: AVCaptureDevice in devices {
                NSLog("Adding menu item %d: %@ (type: %@)", deviceIndex, device.localizedName, device.deviceType.rawValue)
                let deviceMenuItem: NSMenuItem = NSMenuItem(
                    title: device.localizedName, action: #selector(self.deviceMenuChanged), keyEquivalent: ""
                )
                deviceMenuItem.target = self
                deviceMenuItem.representedObject = deviceIndex
                if deviceIndex == currentDeviceIndex {
                    deviceMenuItem.state = NSControl.StateValue.on
                    NSLog("Setting device %d as selected", deviceIndex)
                }
                if deviceIndex < 9 {
                    deviceMenuItem.keyEquivalent = String(deviceIndex + 1)
                }
                deviceMenu.addItem(deviceMenuItem)
                deviceIndex += 1
            }
            
            // Force replace the submenu completely
            self.selectSourceMenu.submenu = deviceMenu
            NSLog("Device menu built with %d items and assigned to selectSourceMenu", deviceMenu.items.count)
            
            // Verify the assignment worked
            if let submenu = self.selectSourceMenu.submenu {
                NSLog("Verification: selectSourceMenu.submenu now has %d items", submenu.items.count)
            } else {
                NSLog("ERROR: selectSourceMenu.submenu is still nil after assignment!")
            }
        }
    }

    // MARK: - Settings Management
    func logSettings(label: String) {
        CPSettingsManager.shared.logSettings(label: label)
    }

    func loadSettings() {
        CPSettingsManager.shared.loadSettings()
    }

    func applySettings() {
        CPSettingsManager.shared.logSettings(label: "applySettings")

        guard let windowManager = windowManager else { return }
        windowManager.setRotation(windowManager.position)
        windowManager.applyMirroring()
        windowManager.fixAspectRatio()
        let settings = CPSettingsManager.shared
        windowManager.applyColorCorrection(brightness: settings.brightness, contrast: settings.contrast, hue: settings.hue)

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
        NSLog("CPAppDelegate: captureImage menu action triggered")
        fileManager.captureImage()
    }

    @IBAction func captureVideo(_ sender: NSMenuItem) {
        guard let captureDir = fileManager.getCaptureDirectory() else {
            errorMessage(message: "Unable to access the capture directory.\n\nPlease check your settings.")
            return
        }
        // Note: If recording fails to start, security-scoped resource cleanup
        // will be handled in didEncounterError for recording-related errors
        captureManager.toggleRecording(captureDirectory: captureDir)
    }
    
    @IBAction func openCaptureFolder(_ sender: NSMenuItem) {
        fileManager.openCaptureFolder()
    }
    
    @IBAction func copy(_ sender: NSMenuItem) {
        if fileManager.copyImageToClipboard() {
            // Optionally show a brief notification that copy was successful
            // The error handling is done in copyImageToClipboard via delegate
        }
    }

    // MARK: - Device Menu Actions
    @objc func deviceMenuChanged(_ sender: NSMenuItem) {
        NSLog("Device Menu changed")
        if sender.state == NSControl.StateValue.on {
            // selected the active device, so nothing to do here
            return
        }

        // set the checkbox on the currently selected device
        guard let submenu = selectSourceMenu.submenu else {
            NSLog("ERROR: selectSourceMenu.submenu is nil")
            return
        }
        for menuItem: NSMenuItem in submenu.items {
            menuItem.state = NSControl.StateValue.off
        }
        sender.state = NSControl.StateValue.on

        guard let deviceIndex = sender.representedObject as? Int else {
            NSLog("ERROR: sender.representedObject is not an Int")
            return
        }
        captureManager.startCaptureWithVideoDevice(deviceIndex: deviceIndex)
    }

    // MARK: - Application Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Skip full initialization if running in test environment
        // This prevents crashes when tests load the app bundle
        if isRunningInTests {
            // Running in test environment - skip hardware initialization
            NSLog("Running in test environment - skipping app initialization")
            // Don't return immediately - keep process alive briefly to allow test runner connection
            // The test runner will terminate the process when tests complete
            return
        }
        
        // Guard: Ensure required outlets are available (they won't be in test environment)
        guard window != nil, playerView != nil else {
            NSLog("Required outlets not available - skipping app initialization")
            return
        }
        
        // Initialize window manager
        windowManager = CPWindowManager()
        windowManager.delegate = self
        windowManager.window = window
        windowManager.playerView = playerView
        
        // Configure translucent title bar (QuickTime Player style)
        windowManager.configureTranslucentTitleBar()
        
        // Pre-create recording control overlay to prevent flash on first use
        windowManager.prepareRecordingControl()
        
        // Initialize capture manager
        captureManager = CPCaptureManager()
        captureManager.delegate = self
        captureManager.previewView = playerView
        
        // Initialize audio manager
        audioManager = CPAudioManager()
        audioManager.delegate = self
        captureManager.audioManager = audioManager
        
        // Initialize file manager
        fileManager = CPCaptureFileManager()
        fileManager.delegate = self
        fileManager.window = window
        fileManager.windowManager = windowManager
        
        // Initialize notification manager
        notificationManager = CPNotificationManager()
        notificationManager.delegate = self
        
        // Initialize display sleep manager
        displaySleepManager = CPDisplaySleepManager()
        displaySleepManager.delegate = self
        displaySleepManager.isFullScreenActive = windowManager.isFullScreenActive
        
        // Initialize preferences controller
        preferencesController = CPPreferencesController(parentWindow: window)
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
        
        // Initialize video content state as false until devices are detected and started
        
        detectVideoDevices()
        // Note: Device selection will happen in didDetectDevices delegate method
        usb.delegate = self
        setupFileMenu()
        setupVideoMenu()
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

        // Move any items with titles containing "ruler"
        if let mainMenu = NSApp.mainMenu {
            var rulerItems: [(NSMenuItem, NSMenu)] = []
            collectMenuItems(in: mainMenu, where: { $0.title.localizedCaseInsensitiveContains("ruler") }, into: &rulerItems)
            if !rulerItems.isEmpty {
                for (item, parent) in rulerItems {
                    parent.removeItem(item)
                    fileMenu.addItem(item)
                }
            }
        }

        removeCloseAllMenuItem(from: fileMenu)
    }

    private func setupVideoMenu() {
        // Find the Video menu and set its delegate
        guard let mainMenu = NSApp.mainMenu,
              let videoMenuItem = mainMenu.item(withTitle: "Video"),
              let videoMenu = videoMenuItem.submenu else { return }
        
        videoMenu.delegate = self
        
        // Respect preference: show always or default to hidden until Option is held
        if CPSettingsManager.shared.alwaysShowImageMenu {
            imageMenu?.isHidden = false
        } else {
            imageMenu?.isHidden = true
        }
    }

    // MARK: - NSMenuDelegate
    func menuWillOpen(_ menu: NSMenu) {
        // Check if this is the Video menu
        if menu.title == "Video" {
            if CPSettingsManager.shared.alwaysShowImageMenu {
                imageMenu?.isHidden = false
                return
            }
            // Show Image menu item if Option key is pressed
            // Check modifier flags from the current event
            if let currentEvent = NSApp.currentEvent {
                let optionKeyPressed = currentEvent.modifierFlags.contains(.option)
                imageMenu?.isHidden = !optionKeyPressed
            } else {
                // Fallback: check current modifier flags
                let optionKeyPressed = NSEvent.modifierFlags.contains(.option)
                imageMenu?.isHidden = !optionKeyPressed
            }
        }
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
        slider.doubleValue = Double(CPSettingsManager.shared.audioVolume)
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
        CPSettingsManager.shared.saveSettings()
    }

    private func updateVolumeSlider() {
        volumeSlider?.doubleValue = Double(CPSettingsManager.shared.audioVolume)
    }

    private func requestAudioAccessIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            detectAudioDevices()
        case .restricted, .denied:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    self.detectAudioDevices()
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
    
    @IBAction func showColorCorrection(_ sender: NSMenuItem) {
        if colorCorrectionController == nil {
            colorCorrectionController = CPColorCorrectionController(deviceName: deviceName)
            colorCorrectionController?.delegate = self
        } else {
            // Update device name if it changed
            colorCorrectionController?.deviceName = deviceName
        }
        colorCorrectionController?.showWindow()
    }

    // Help viewer instance
    private var helpViewer: CPHelpViewerController?
    
    // Handle the standard help action - show HTML manual in WebView
    @IBAction func showHelp(_ sender: Any?) {
        print("CPAppDelegate: showHelp called")
        
        // Show HTML help in WebView
        if let existingViewer = helpViewer, let window = existingViewer.window, window.isVisible {
            window.makeKeyAndOrderFront(sender)
            print("CPAppDelegate: Showing existing help window")
        } else {
            print("CPAppDelegate: Creating new help viewer")
            let viewer = CPHelpViewerController()
            viewer.delegate = self
            helpViewer = viewer
            viewer.showWindow(sender)
            print("CPAppDelegate: showWindow called")
        }
    }
    

    func applicationWillTerminate(_ notification: Notification) {
        displaySleepManager?.cleanup()
        windowManager?.hideRecordingControl()
        windowManager?.updateWindowFrameSettings()
        CPSettingsManager.shared.saveSettings()
    }


    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - CPCaptureManagerDelegate
extension CPAppDelegate {
    func captureManager(_ manager: CPCaptureManager, didDetectDevices devices: [AVCaptureDevice]) {
        NSLog("didDetectDevices called with %d devices", devices.count)
        // Build device menu
        let currentDeviceIndex: Int
        if captureSession != nil, let currentInput = input {
            let currentDevice = currentInput.device
            // If we have an existing session, prefer the current device, but fall back to saved device if not found
            currentDeviceIndex = devices.firstIndex(of: currentDevice) ?? manager.getPreferredDefaultDeviceIndex(from: devices, savedDeviceName: CPSettingsManager.shared.savedDeviceName)
            NSLog("Using existing device index: %d", currentDeviceIndex)
        } else {
            // On launch, try to restore the saved device selection
            // Check both savedDeviceName (from UserDefaults) and deviceName (current value)
            let settings = CPSettingsManager.shared
            let savedDeviceName = settings.savedDeviceName.isEmpty || settings.savedDeviceName == "-" 
                ? settings.deviceName 
                : settings.savedDeviceName
            currentDeviceIndex = manager.getPreferredDefaultDeviceIndex(from: devices, savedDeviceName: savedDeviceName)
            NSLog("Using preferred default device index: %d (saved device: '%@')", currentDeviceIndex, savedDeviceName)
        }
        buildDeviceMenu(devices: devices, currentDeviceIndex: currentDeviceIndex)
        
        // Start capture with the preferred device if not already running
        if captureSession == nil {
            NSLog("Starting capture with preferred device at index %d", currentDeviceIndex)
            manager.startCaptureWithVideoDevice(deviceIndex: currentDeviceIndex)
            // Ensure audio is initialized when video capture starts
            audioManager.detectAudioDevices()
            // Force audio session configuration on startup to ensure it's properly initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.audioManager.ensureAudioSessionConfigured()
            }
        } else {
            NSLog("Capture session already exists, not starting new device")
        }
    }
    
    func captureManager(_ manager: CPCaptureManager, didChangeDevice device: AVCaptureDevice, deviceIndex: Int) {
        // Update device menu selection
        if let menu = selectSourceMenu.submenu {
            for (index, item) in menu.items.enumerated() {
                item.state = (index == deviceIndex) ? .on : .off
            }
        }
        // Update audio preferences for the new video device
        audioManager.updatePreferredInputFromVideo(videoDevice: device)
        // Force audio session configuration to ensure it's properly set up after video device change
        audioManager.ensureAudioSessionConfigured()
        // Connect window manager to capture layer and input
        windowManager.captureLayer = captureManager.getPreviewLayer()
        windowManager.videoInput = captureManager.getInput()
        
        // Apply rotation NOW that capture layer is available
        // This ensures rotation is applied correctly on startup (default position is 0 = portrait)
        windowManager.setRotation(windowManager.position)
        windowManager.applyMirroring()
        windowManager.fixAspectRatio()
        
        // Connect file manager to capture session and layer
        fileManager.captureSession = captureManager.captureSession
        fileManager.captureLayer = captureManager.getPreviewLayer()
        
        // Load device-specific color correction settings
        let deviceNameToUse = device.localizedName
        CPSettingsManager.shared.loadColorCorrection(forDevice: deviceNameToUse)
        windowManager?.applyColorCorrection(
            brightness: CPSettingsManager.shared.brightness,
            contrast: CPSettingsManager.shared.contrast,
            hue: CPSettingsManager.shared.hue
        )
        
        // Update color correction controller if it exists
        if let controller = colorCorrectionController {
            controller.deviceName = deviceNameToUse
        }
    }
    
    func captureManager(_ manager: CPCaptureManager, didStartRecordingTo url: URL) {
        updateCaptureVideoMenuItemState()
        // Show recording control when recording starts (if enabled in settings)
        if CPSettingsManager.shared.showVideoCaptureControls {
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let windowManager = self.windowManager,
                      windowManager.window != nil else { return }
                windowManager.showRecordingControl()
                // Update to recording state immediately after showing (since didChangeRecordingState
                // may have been called before the control was shown)
                windowManager.updateRecordingControlState(isRecording: true)
            }
        }
        let filename = url.lastPathComponent
        notificationManager.sendNotification(title: "Video Recording", body: "Recording started: \(filename)", sound: true)
    }
    
    func captureManager(_ manager: CPCaptureManager, didFinishRecordingTo url: URL, error: Error?) {
        updateCaptureVideoMenuItemState()
        // Stop accessing security-scoped resource after video recording completes
        fileManager.stopAccessingSecurityScopedResource()
        if error == nil {
            let filename = url.lastPathComponent
            notificationManager.sendNotification(title: "Video Recording", body: "Recording saved: \(filename)", sound: true)
        }
    }
    
    func captureManager(_ manager: CPCaptureManager, didEncounterError error: Error, message: String) {
        // Check if this is a recording-related error (codes -2, -3, -4, -8)
        // If recording failed to start, clean up security-scoped resource
        let nsError = error as NSError
        let recordingErrorCodes: [Int] = [-2, -3, -4, -8] // Recording-related error codes
        if recordingErrorCodes.contains(nsError.code) && !manager.isRecording {
            // Recording failed before it could start, clean up security-scoped resource
            fileManager.stopAccessingSecurityScopedResource()
        }
        errorMessage(message: message)
    }
    
    func captureManager(_ manager: CPCaptureManager, needsAudioDeviceUpdateFor videoDevice: AVCaptureDevice) {
        // updatePreferredInputFromVideo handles audio configuration internally
        audioManager.updatePreferredInputFromVideo(videoDevice: videoDevice)
        // Ensure audio is fully initialized
        audioManager.detectAudioDevices()
    }
    
    func captureManager(_ manager: CPCaptureManager, needsSettingsApplication: Void) {
        applySettings()
    }
    
    func captureManager(_ manager: CPCaptureManager, needsWindowTitleUpdate title: String) {
        windowManager.setWindowTitle(title)
    }
    
    func captureManager(_ manager: CPCaptureManager, needsDeviceNameUpdate name: String) {
        deviceName = name
        
        // Update color correction controller device name
        colorCorrectionController?.deviceName = name
    }
    
    func captureManager(_ manager: CPCaptureManager, didChangeRecordingState isRecording: Bool) {
        updateCaptureVideoMenuItemState()
        windowManager?.updateRecordingControlState(isRecording: isRecording)
    }
    
}

// MARK: - CPAudioManagerDelegate
extension CPAppDelegate {
    func audioManager(_ manager: CPAudioManager, didDetectInputDevices devices: [AVCaptureDevice]) {
        // Devices detected, menus will be updated via needsMenuUpdateForInput
        // Ensure recording audio input is attached now that audio manager is ready
        // This prevents screen blanking on first video capture
        captureManager.ensureRecordingAudioInputAttached()
    }
    
    func audioManager(_ manager: CPAudioManager, didDetectOutputDevices devices: [AudioOutputDeviceInfo]) {
        // Devices detected, menus will be updated via needsMenuUpdateForOutput
    }
    
    func audioManager(_ manager: CPAudioManager, didChangeInput device: AVCaptureDevice?) {
        // Input changes are handled within CPAudioManager; nothing additional needed here.
    }
    
    func audioManager(_ manager: CPAudioManager, didChangeOutput deviceUID: String?) {
        // Output changed
    }
    
    func audioManager(_ manager: CPAudioManager, needsMenuUpdateForInput devices: [AVCaptureDevice], selectedUID: String?) {
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
    
    func audioManager(_ manager: CPAudioManager, needsMenuUpdateForOutput devices: [AudioOutputDeviceInfo], selectedUID: String?) {
        let menu = NSMenu()
        let settings = CPSettingsManager.shared
        
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
            
            // Add "Follow System Output" option at the top
            let followSystemItem = NSMenuItem(
                title: "Follow System Output",
                action: #selector(audioOutputMenuChanged),
                keyEquivalent: ""
            )
            followSystemItem.target = self
            followSystemItem.representedObject = "SYSTEM_DEFAULT"
            followSystemItem.state = settings.followSystemOutput ? .on : .off
            menu.addItem(followSystemItem)
            
            // Add separator
            menu.addItem(NSMenuItem.separator())
            
            // Add all devices
            for device in devices {
                let item = NSMenuItem(
                    title: device.name,
                    action: #selector(audioOutputMenuChanged),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device.uid
                // Show as selected if it matches selectedUID, or if following system and this is the system default
                let isSelected = (device.uid == selectedUID) || (settings.followSystemOutput && device.uid == selectedUID)
                item.state = isSelected ? .on : .off
                menu.addItem(item)
            }
        }
        selectAudioOutputMenu.submenu = menu
    }
    
    func audioManager(_ manager: CPAudioManager, didChangeMuteState muted: Bool) {
        muteAudioMenuItem?.state = muted ? .on : .off
    }
    
    func audioManager(_ manager: CPAudioManager, didChangeVolume volume: Float) {
        updateVolumeSlider()
    }
}

// MARK: - CPWindowManagerDelegate
extension CPAppDelegate {
    func windowManager(_ manager: CPWindowManager, willEnterFullScreen: Bool) {
        displaySleepManager.isFullScreenActive = manager.isFullScreenActive
        displaySleepManager.handleWillEnterFullScreen()
    }

    func windowManager(_ manager: CPWindowManager, didEnterFullScreen: Bool) {
        displaySleepManager.isFullScreenActive = manager.isFullScreenActive
    }
    
    func windowManager(_ manager: CPWindowManager, willExitFullScreen: Bool) {
        displaySleepManager.handleWillExitFullScreen()
    }

    func windowManager(_ manager: CPWindowManager, didExitFullScreen: Bool) {
        displaySleepManager.isFullScreenActive = manager.isFullScreenActive
        displaySleepManager.handleDidExitFullScreen()
        windowManager.updateWindowFrameSettings()
    }
    
    func windowManager(_ manager: CPWindowManager, didChangeFrame frame: NSRect) {
        // Frame changed, settings will be updated automatically via notifications
    }
    
    func windowManager(_ manager: CPWindowManager, needsSettingsUpdate: Void) {
        applySettings()
    }
    
    func windowManager(_ manager: CPWindowManager, didChangeBorderless isBorderless: Bool) {
        borderlessMenu.state = convertToNSControlStateValue(
            (isBorderless ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }
    
    func windowManager(_ manager: CPWindowManager, didChangeRotation position: Int) {
        // Rotation changed, settings applied via needsSettingsUpdate
    }
    
    func windowManager(_ manager: CPWindowManager, didChangeMirroring isMirrored: Bool) {
        mirroredMenu.state = convertToNSControlStateValue(
            (isMirrored ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }
    
    func windowManager(_ manager: CPWindowManager, didChangeUpsideDown isUpsideDown: Bool) {
        upsideDownMenu.state = convertToNSControlStateValue(
            (isUpsideDown ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }
    
    func windowManager(_ manager: CPWindowManager, didChangeAspectRatioFixed isFixed: Bool) {
        aspectRatioFixedMenu.state = convertToNSControlStateValue(
            (isFixed ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }
    
    func windowManager(_ manager: CPWindowManager, didClickRecordingControl: Void) {
        // Toggle recording when control is clicked
        guard let captureDir = fileManager.getCaptureDirectory() else {
            errorMessage(message: "Unable to access the capture directory.\n\nPlease check your settings.")
            return
        }
        captureManager.toggleRecording(captureDirectory: captureDir)
    }
}

// MARK: - CPCaptureFileManagerDelegate
extension CPAppDelegate {
    func captureFileManager(_ manager: CPCaptureFileManager, didSaveImageTo url: URL, filename: String) {
        NSLog("Image saved to: %@", url.path)
    }
    
    func captureFileManager(_ manager: CPCaptureFileManager, didEncounterError error: Error, message: String) {
        errorMessage(message: message)
    }
    
    func captureFileManager(_ manager: CPCaptureFileManager, needsNotification title: String, body: String, sound: Bool) {
        notificationManager.sendNotification(title: title, body: body, sound: sound)
    }
}

// MARK: - CPNotificationManagerDelegate
extension CPAppDelegate {
    func notificationManager(_ manager: CPNotificationManager, didRequestPermissions granted: Bool, error: Error?) {
        // Permissions requested, can handle if needed
    }
    
    func notificationManager(_ manager: CPNotificationManager, didSendNotification title: String, body: String, error: Error?) {
        // Notification sent, can handle if needed
    }
}

// MARK: - CPDisplaySleepManagerDelegate
extension CPAppDelegate {
    func displaySleepManager(_ manager: CPDisplaySleepManager, didChangeState isPreventing: Bool) {
        // State changed, can handle if needed
    }
    
    func displaySleepManager(_ manager: CPDisplaySleepManager, needsNotification title: String, body: String, sound: Bool) {
        notificationManager.sendNotification(title: title, body: body, sound: sound)
    }
    
    func displaySleepManager(_ manager: CPDisplaySleepManager, needsErrorDisplay message: String) {
        errorMessage(message: message)
    }
    
    func displaySleepManager(_ manager: CPDisplaySleepManager, needsMenuItemUpdate isPreventing: Bool) {
        displaySleepMenuItem?.state = isPreventing ? .on : .off
    }
    
    func displaySleepManager(_ manager: CPDisplaySleepManager, needsMenuItemEnabled enabled: Bool) {
        displaySleepMenuItem?.isEnabled = enabled
    }
}

// MARK: - CPColorCorrectionControllerDelegate
extension CPAppDelegate {
    func colorCorrectionController(_ controller: CPColorCorrectionController, didChangeBrightness brightness: Float, contrast: Float, hue: Float) {
        windowManager?.applyColorCorrection(brightness: brightness, contrast: contrast, hue: hue)
        CPSettingsManager.shared.saveSettings()
    }
}

// MARK: - CPHelpViewerDelegate
extension CPAppDelegate: CPHelpViewerDelegate {
    func helpViewerDidClose(_ helpViewer: CPHelpViewerController) {
        // Help viewer was closed, clear reference
        if self.helpViewer === helpViewer {
            self.helpViewer = nil
        }
    }
}

// MARK: - CPPreferencesControllerDelegate
extension CPAppDelegate {
    func preferencesController(_ controller: CPPreferencesController, didSavePreferences: Void) {
        // Hide control if setting was disabled
        if !CPSettingsManager.shared.showVideoCaptureControls {
            windowManager?.hideRecordingControl()
        }
        // Update Image menu visibility according to new setting
        if CPSettingsManager.shared.alwaysShowImageMenu {
            imageMenu?.isHidden = false
        } else {
            imageMenu?.isHidden = true
        }
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

