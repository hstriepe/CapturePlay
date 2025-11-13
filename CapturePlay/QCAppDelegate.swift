import AVFoundation
import AVKit
import Cocoa
import CoreAudio
import IOKit.pwr_mgt
import UserNotifications

// MARK: - QCAppDelegate Class
@NSApplicationMain
class QCAppDelegate: NSObject, NSApplicationDelegate, QCUsbWatcherDelegate, AVCaptureFileOutputRecordingDelegate, UNUserNotificationCenterDelegate {

    // MARK: - USB Watcher
    let usb: QCUsbWatcher = QCUsbWatcher()
    func deviceCountChanged() {
        self.detectVideoDevices()
        self.startCaptureWithVideoDevice(defaultDevice: selectedDeviceIndex)
        self.detectAudioDevices()
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

    // MARK: - Settings Properties
    var isMirrored: Bool {
        get { QCSettingsManager.shared.isMirrored }
        set { QCSettingsManager.shared.setMirrored(newValue) }
    }
    var isUpsideDown: Bool {
        get { QCSettingsManager.shared.isUpsideDown }
        set { QCSettingsManager.shared.setUpsideDown(newValue) }
    }
    var position: Int {
        get { QCSettingsManager.shared.position }
        set { QCSettingsManager.shared.setPosition(newValue) }
    }
    var isBorderless: Bool {
        get { QCSettingsManager.shared.isBorderless }
        set { QCSettingsManager.shared.setBorderless(newValue) }
    }
    var isAspectRatioFixed: Bool {
        get { QCSettingsManager.shared.isAspectRatioFixed }
        set { QCSettingsManager.shared.setAspectRatioFixed(newValue) }
    }
    var deviceName: String {
        get { QCSettingsManager.shared.deviceName }
        set { QCSettingsManager.shared.setDeviceName(newValue) }
    }

    // MARK: - Window Properties
    var defaultBorderStyle: NSWindow.StyleMask = NSWindow.StyleMask.closable
    var windowTitle: String = "CapturePlay"
    let defaultDeviceIndex: Int = 0
    var selectedDeviceIndex: Int = 0

    var savedDeviceName: String = "-"
    var devices: [AVCaptureDevice]!
    var captureSession: AVCaptureSession!
    var captureLayer: AVCaptureVideoPreviewLayer!

    var input: AVCaptureDeviceInput!
    private var audioCaptureInput: AVCaptureDeviceInput?
    private var audioPreviewOutput: AVCaptureAudioPreviewOutput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var audioInputDevices: [AVCaptureDevice] = []
    private var audioOutputDevices: [AudioOutputDeviceInfo] = []
    private var selectedAudioInputUID: String?
    private var selectedAudioOutputUID: String?
    private var currentVideoDevice: AVCaptureDevice?
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var isRecording: Bool = false {
        didSet {
            updateCaptureVideoMenuItemState()
        }
    }
    private var isPreventingDisplaySleep: Bool = false {
        didSet { updateDisplaySleepMenuItemState() }
    }
    private var displaySleepStateBeforeFullScreen: Bool?
    private var isFullScreenActive: Bool = false
    private var cursorHiddenForFullScreen: Bool = false
    private var gameModeActivity: NSObjectProtocol?
    private var volumeSlider: NSSlider?

    // MARK: - Error Handling
    func errorMessage(message: String) {
        let popup: NSAlert = NSAlert()
        popup.messageText = message
        popup.runModal()
    }

    // MARK: - Device Management
    func detectVideoDevices() {
        NSLog("Detecting video devices...")
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified)
        self.devices = discoverySession.devices
        if devices.isEmpty {
            let popup: NSAlert = NSAlert()
            popup.messageText =
                "Unfortunately, you don't appear to have any cameras connected. Goodbye for now!"
            popup.runModal()
            NSApp.terminate(nil)
        } else {
            NSLog("%d devices found", devices.count)
        }

        let deviceMenu: NSMenu = NSMenu()
        var deviceIndex: Int = 0

        // Here we need to keep track of the current device (if selected) in order to keep it checked in the menu
        var currentDevice: AVCaptureDevice = self.devices[defaultDeviceIndex]
        if self.captureSession != nil {
            currentDevice = (self.captureSession.inputs[0] as! AVCaptureDeviceInput).device
        } else {
            NSLog("first time - loadSettings")
            self.loadSettings()
            self.applyDisplaySleepPreferenceFromSettings()
        }
        self.selectedDeviceIndex = defaultDeviceIndex

        for device: AVCaptureDevice in self.devices {
            let deviceMenuItem: NSMenuItem = NSMenuItem(
                title: device.localizedName, action: #selector(deviceMenuChanged), keyEquivalent: ""
            )
            deviceMenuItem.target = self
            deviceMenuItem.representedObject = deviceIndex
            if device == currentDevice {
                deviceMenuItem.state = NSControl.StateValue.on
                self.selectedDeviceIndex = deviceIndex
            }
            if deviceIndex < 9 {
                deviceMenuItem.keyEquivalent = String(deviceIndex + 1)
            }
            deviceMenu.addItem(deviceMenuItem)
            deviceIndex += 1
        }
        selectSourceMenu.submenu = deviceMenu
    }

    func startCaptureWithVideoDevice(defaultDevice: Int) {
        NSLog("Starting capture with device index %d", defaultDevice)
        let device: AVCaptureDevice = self.devices[defaultDevice]

        if captureSession != nil {

            // if we are "restarting" a session but the device is the same exit early
            let currentDevice: AVCaptureDevice =
                (self.captureSession.inputs[0] as! AVCaptureDeviceInput).device
            guard currentDevice != device else { return }

            captureSession.stopRunning()
        }
        captureSession = AVCaptureSession()
        audioCaptureInput = nil
        audioPreviewOutput = nil
        movieFileOutput = nil

        do {
            self.input = try AVCaptureDeviceInput(device: device)
            self.captureSession.beginConfiguration()
            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
            }
            
            // Add movie file output for video recording
            let movieOutput = AVCaptureMovieFileOutput()
            if self.captureSession.canAddOutput(movieOutput) {
                self.captureSession.addOutput(movieOutput)
                self.movieFileOutput = movieOutput
            }
            
            self.captureSession.commitConfiguration()
            self.captureLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
            self.captureLayer.connection?.automaticallyAdjustsVideoMirroring = false
            self.captureLayer.connection?.isVideoMirrored = false

            self.playerView.layer = self.captureLayer
            self.playerView.layer?.backgroundColor = CGColor.black
            self.windowTitle = String(format: "CapturePlay: [%@]", device.localizedName)
            self.window.title = self.windowTitle
            self.deviceName = device.localizedName
            self.currentVideoDevice = device
            self.updatePreferredAudioInputFromVideoIfNeeded(with: device)
            self.detectAudioDevices()
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            self.applySettings()
        } catch {
            NSLog("Error while opening device")
            self.errorMessage(
                message:
                    "Unfortunately, there was an error when trying to access the camera. Try again or select a different one."
            )
        }
    }

    // MARK: - Settings Management
    func logSettings(label: String) {
        QCSettingsManager.shared.logSettings(label: label)
    }

    func loadSettings() {
        QCSettingsManager.shared.loadSettings()

        if self.isBorderless {
            self.removeBorder()
        }

        let savedW = QCSettingsManager.shared.frameWidth
        let savedH = QCSettingsManager.shared.frameHeight
        if 100 < savedW && 100 < savedH {
            let savedX = QCSettingsManager.shared.frameX
            let savedY = QCSettingsManager.shared.frameY
            NSLog("loaded : x:%f,y:%f,w:%f,h:%f", savedX, savedY, savedW, savedH)
            var currentSize: CGSize = self.window.contentLayoutRect.size
            currentSize.width = CGFloat(savedW)
            currentSize.height = CGFloat(savedH)
            self.window.setContentSize(currentSize)
            self.window.setFrameOrigin(NSPoint(x: CGFloat(savedX), y: CGFloat(savedY)))
        }
    }

    func applySettings() {
        QCSettingsManager.shared.logSettings(label: "applySettings")

        self.setRotation(self.position)
        self.captureLayer.connection?.isVideoMirrored = isMirrored
        self.fixAspectRatio()

        self.borderlessMenu.state = convertToNSControlStateValue(
            (isBorderless ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        self.mirroredMenu.state = convertToNSControlStateValue(
            (isMirrored ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        self.upsideDownMenu.state = convertToNSControlStateValue(
            (isUpsideDown ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        self.aspectRatioFixedMenu.state = convertToNSControlStateValue(
            (isAspectRatioFixed
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
        applyDisplaySleepPreferenceFromSettings(force: true)
        detectAudioDevices()
    }

    // MARK: - Display Actions
    @IBAction func mirrorHorizontally(_ sender: NSMenuItem) {
        NSLog("Mirror image menu item selected")
        isMirrored = !isMirrored
        self.applySettings()
    }

    func setRotation(_ position: Int) {
        switch position {
        case 1:
            if !isUpsideDown {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.landscapeLeft
            } else {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.landscapeRight
            }
            break
        case 2:
            if !isUpsideDown {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.portraitUpsideDown
            } else {
                self.captureLayer.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
            }
            break
        case 3:
            if !isUpsideDown {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.landscapeRight
            } else {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.landscapeLeft
            }
            break
        case 0:
            if !isUpsideDown {
                self.captureLayer.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
            } else {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.portraitUpsideDown
            }
            break
        default: break
        }
    }

    @IBAction func mirrorVertically(_ sender: NSMenuItem) {
        NSLog("Mirror image vertically menu item selected")
        isUpsideDown = !isUpsideDown
        self.applySettings()
    }

    func swapWH() {
        var currentSize: CGSize = self.window.contentLayoutRect.size
        swap(&currentSize.height, &currentSize.width)
        self.window.setContentSize(currentSize)
    }

    @IBAction func rotateLeft(_ sender: NSMenuItem) {
        NSLog("Rotate Left menu item selected with position %d", position)
        position = position - 1
        if position == -1 { position = 3 }
        self.swapWH()
        self.applySettings()
    }

    @IBAction func rotateRight(_ sender: NSMenuItem) {
        NSLog("Rotate Right menu item selected with position %d", position)
        position = position + 1
        if position == 4 { position = 0 }
        self.swapWH()
        self.applySettings()
    }

    // MARK: - Display Helpers
    private func addBorder() {
        window.styleMask = defaultBorderStyle
        window.title = self.windowTitle
        self.window.level = convertToNSWindowLevel(Int(CGWindowLevelForKey(.normalWindow)))
        window.isMovableByWindowBackground = false
    }

    private func removeBorder() {
        defaultBorderStyle = window.styleMask
        self.window.styleMask = [NSWindow.StyleMask.borderless, NSWindow.StyleMask.resizable]
        self.window.level = convertToNSWindowLevel(Int(CGWindowLevelForKey(.maximumWindow)))
        window.isMovableByWindowBackground = true
    }

    @IBAction func borderless(_ sender: NSMenuItem) {
        NSLog("Borderless menu item selected")
        if self.window.styleMask.contains(.fullScreen) {
            NSLog("Ignoring borderless command as window is full screen")
            return
        }
        isBorderless = !isBorderless
        sender.state = convertToNSControlStateValue(
            (isBorderless ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        if isBorderless {
            removeBorder()
        } else {
            addBorder()
        }
        fixAspectRatio()
    }

    @IBAction func enterFullScreen(_ sender: NSMenuItem) {
        NSLog("Enter full screen menu item selected")
        playerView.window?.toggleFullScreen(self)
        // no effect when borderless is enabled ?
    }

    @IBAction func toggleFixAspectRatio(_ sender: NSMenuItem) {
        isAspectRatioFixed = !isAspectRatioFixed
        sender.state = convertToNSControlStateValue(
            (isAspectRatioFixed
                ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        fixAspectRatio()
    }

    func isLandscape() -> Bool {
        return position % 2 == 0
    }

    func fixAspectRatio() {
        if isAspectRatioFixed, #available(OSX 10.15, *) {
            let height: Int32 = input.device.activeFormat.formatDescription.dimensions.height
            let width: Int32 = input.device.activeFormat.formatDescription.dimensions.width
            let size: NSSize =
                self.isLandscape()
                ? NSMakeSize(CGFloat(width), CGFloat(height))
                : NSMakeSize(CGFloat(height), CGFloat(width))
            self.window.contentAspectRatio = size

            let ratio: CGFloat = CGFloat(Float(width) / Float(height))
            var currentSize: CGSize = self.window.contentLayoutRect.size
            if self.isLandscape() {
                currentSize.height = currentSize.width / ratio
            } else {
                currentSize.height = currentSize.width * ratio
            }
            NSLog(
                "fixAspectRatio : %f - %d,%d - %f,%f - %f,%f", ratio, width, height, size.width,
                size.height, currentSize.width, currentSize.height)
            self.window.setContentSize(currentSize)
        } else {
            self.window.contentResizeIncrements = NSMakeSize(1.0, 1.0)
        }
    }

    @IBAction func fitToActualSize(_ sender: NSMenuItem) {
        if #available(OSX 10.15, *) {
            let height: Int32 = input.device.activeFormat.formatDescription.dimensions.height
            let width: Int32 = input.device.activeFormat.formatDescription.dimensions.width
            var currentSize: CGSize = self.window.contentLayoutRect.size
            currentSize.width = CGFloat(self.isLandscape() ? width : height)
            currentSize.height = CGFloat(self.isLandscape() ? height : width)
            self.window.setContentSize(currentSize)
        }
    }

    @IBAction func saveImage(_ sender: NSMenuItem) {
        if self.window.styleMask.contains(.fullScreen) {
            NSLog("Save is not supported as window is full screen")
            return
        }

        if captureSession != nil {
            if #available(OSX 10.12, *) {
                // turn borderless on, capture image, return border to previous state
                let borderlessState: Bool = self.isBorderless
                if borderlessState == false {
                    NSLog("Removing border")
                    self.removeBorder()
                }

                /* Pause the RunLoop for 0.1 sec to let the window repaint after removing the border - I'm not a fan of this approach
                   but can't find another way to listen to an event for the window being updated. PRs welcome :) */
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))

                let cgImage: CGImage? = CGWindowListCreateImage(
                    CGRect.null, .optionIncludingWindow, CGWindowID(self.window.windowNumber),
                    [.boundsIgnoreFraming, .bestResolution])

                if borderlessState == false {
                    self.addBorder()
                }

                DispatchQueue.main.async {
                    let now: Date = Date()
                    let dateFormatter: DateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let date: String = dateFormatter.string(from: now)
                    dateFormatter.dateFormat = "h.mm.ss a"
                    let time: String = dateFormatter.string(from: now)

                    let panel: NSSavePanel = NSSavePanel()
                    panel.nameFieldStringValue = String(
                        format: "CapturePlay Image %@ at %@.png", date, time)
                    panel.beginSheetModal(for: self.window) {
                        (result: NSApplication.ModalResponse) in
                        if result == NSApplication.ModalResponse.OK {
                            NSLog(panel.url!.absoluteString)
                            let destination: CGImageDestination? = CGImageDestinationCreateWithURL(
                                panel.url! as CFURL, UTType.png.identifier as CFString, 1, nil)
                            if destination == nil {
                                NSLog(
                                    "Could not write file - destination returned from CGImageDestinationCreateWithURL was nil"
                                )
                                self.errorMessage(
                                    message:
                                        "Unfortunately, the image could not be saved to this location."
                                )
                            } else {
                                CGImageDestinationAddImage(destination!, cgImage!, nil)
                                CGImageDestinationFinalize(destination!)
                            }
                        }
                    }
                }
            } else {
                let popup: NSAlert = NSAlert()
                popup.messageText =
                    "Unfortunately, saving images is only supported in Mac OSX 10.12 (Sierra) and higher."
                popup.runModal()
            }
        }
    }

    private func expandTildePath(_ path: String) -> String {
        if path.hasPrefix("~") {
            let homePath = NSHomeDirectory()
            if path == "~" {
                return homePath
            } else if path.hasPrefix("~/") {
                return (homePath as NSString).appendingPathComponent(String(path.dropFirst(2)))
            } else {
                // Handle ~username format (less common)
                return (path as NSString).expandingTildeInPath
            }
        }
        return path
    }
    
    private func getCaptureDirectory() -> URL? {
        let settings = QCSettingsManager.shared
        
        // First, try to resolve security-scoped bookmark if available
        if let bookmarkData = settings.captureImageDirectoryBookmark {
            var isStale = false
            do {
                let bookmarkURL = try URL(resolvingBookmarkData: bookmarkData, options: [.withoutUI, .withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if isStale {
                    NSLog("WARNING: Security-scoped bookmark is stale, will need to be refreshed")
                }
                
                // Start accessing the security-scoped resource
                guard bookmarkURL.startAccessingSecurityScopedResource() else {
                    NSLog("ERROR: Failed to start accessing security-scoped resource: %@", bookmarkURL.path)
                    return nil
                }
                
                // Ensure directory exists and is writable
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: bookmarkURL.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        if FileManager.default.isWritableFile(atPath: bookmarkURL.path) {
                            NSLog("Using security-scoped capture directory: %@", bookmarkURL.path)
                            return bookmarkURL
                        } else {
                            bookmarkURL.stopAccessingSecurityScopedResource()
                            NSLog("ERROR: Security-scoped directory is not writable: %@", bookmarkURL.path)
                            return nil
                        }
                    } else {
                        bookmarkURL.stopAccessingSecurityScopedResource()
                        NSLog("ERROR: Security-scoped path exists but is not a directory: %@", bookmarkURL.path)
                        return nil
                    }
                } else {
                    // Try to create directory
                    do {
                        try FileManager.default.createDirectory(at: bookmarkURL, withIntermediateDirectories: true, attributes: nil)
                        if FileManager.default.fileExists(atPath: bookmarkURL.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                            if FileManager.default.isWritableFile(atPath: bookmarkURL.path) {
                                NSLog("Created security-scoped capture directory: %@", bookmarkURL.path)
                                return bookmarkURL
                            } else {
                                bookmarkURL.stopAccessingSecurityScopedResource()
                                NSLog("ERROR: Created directory but it is not writable: %@", bookmarkURL.path)
                                return nil
                            }
                        } else {
                            bookmarkURL.stopAccessingSecurityScopedResource()
                            NSLog("ERROR: Directory creation reported success but directory does not exist: %@", bookmarkURL.path)
                            return nil
                        }
                    } catch {
                        bookmarkURL.stopAccessingSecurityScopedResource()
                        NSLog("ERROR: Failed to create security-scoped directory: %@ - %@", bookmarkURL.path, error.localizedDescription)
                        return nil
                    }
                }
            } catch {
                NSLog("ERROR: Failed to resolve security-scoped bookmark: %@", error.localizedDescription)
                // Fall through to try path-based access
            }
        }
        
        // Fall back to path-based access (for folders with entitlements like Pictures, Downloads)
        var directoryPath: String = settings.captureImageDirectory
        
        // If no directory is set, use default ~/Pictures/CapturePlay
        // Note: Pictures folder has sandbox entitlement, so it works without user selection
        if directoryPath.isEmpty {
            let homePath = NSHomeDirectory()
            directoryPath = (homePath as NSString).appendingPathComponent("Pictures/CapturePlay")
            NSLog("Using default capture directory: %@", directoryPath)
        } else {
            // Expand tilde if present
            let originalPath = directoryPath
            directoryPath = expandTildePath(directoryPath)
            if originalPath != directoryPath {
                NSLog("Expanded tilde path: %@ -> %@", originalPath, directoryPath)
            }
        }
        
        let directoryURL = URL(fileURLWithPath: directoryPath)
        
        // Ensure directory exists
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directoryPath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                // Check if we can write to the directory
                if !FileManager.default.isWritableFile(atPath: directoryPath) {
                    NSLog("ERROR: Capture directory is not writable: %@", directoryPath)
                    return nil
                }
                NSLog("Using existing capture directory: %@", directoryPath)
                return directoryURL
            } else {
                NSLog("ERROR: Capture directory path exists but is not a directory: %@", directoryPath)
                return nil
            }
        } else {
            // Create directory
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                NSLog("Successfully created capture directory: %@", directoryPath)
                
                // Verify it was created and is writable
                if FileManager.default.fileExists(atPath: directoryPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                    if FileManager.default.isWritableFile(atPath: directoryPath) {
                        return directoryURL
                    } else {
                        NSLog("ERROR: Created directory but it is not writable: %@", directoryPath)
                        return nil
                    }
                } else {
                    NSLog("ERROR: Directory creation reported success but directory does not exist: %@", directoryPath)
                    return nil
                }
            } catch {
                NSLog("ERROR: Failed to create capture directory: %@ - %@", directoryPath, error.localizedDescription)
                NSLog("ERROR: Error details: %@", String(describing: error))
                return nil
            }
        }
    }

    @IBAction func captureImage(_ sender: NSMenuItem) {
        if self.window.styleMask.contains(.fullScreen) {
            NSLog("Capture is not supported as window is full screen")
            return
        }

        guard let captureDir = getCaptureDirectory() else {
            let settings = QCSettingsManager.shared
            let dirPath = settings.captureImageDirectory.isEmpty ? "~/Pictures/CapturePlay" : settings.captureImageDirectory
            errorMessage(message: "Unable to access or create the capture directory: \(dirPath)\n\nPlease check that:\n• The path is correct\n• You have write permissions\n• The directory can be created\n\nNote: For sandboxed apps, you may need to select the folder via the Browse button in Preferences to grant access.")
            return
        }

        if captureSession != nil {
            if #available(OSX 10.12, *) {
                // turn borderless on, capture image, return border to previous state
                let borderlessState: Bool = self.isBorderless
                if borderlessState == false {
                    NSLog("Removing border")
                    self.removeBorder()
                }

                /* Pause the RunLoop for 0.1 sec to let the window repaint after removing the border - I'm not a fan of this approach
                   but can't find another way to listen to an event for the window being updated. PRs welcome :) */
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))

                let cgImage: CGImage? = CGWindowListCreateImage(
                    CGRect.null, .optionIncludingWindow, CGWindowID(self.window.windowNumber),
                    [.boundsIgnoreFraming, .bestResolution])

                if borderlessState == false {
                    self.addBorder()
                }

                DispatchQueue.main.async {
                    let now: Date = Date()
                    let dateFormatter: DateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let date: String = dateFormatter.string(from: now)
                    dateFormatter.dateFormat = "HH.mm.ss"
                    let time: String = dateFormatter.string(from: now)

                    let filename = String(format: "CapturePlay Image %@ at %@.png", date, time)
                    let fileURL = captureDir.appendingPathComponent(filename)

                    let destination: CGImageDestination? = CGImageDestinationCreateWithURL(
                        fileURL as CFURL, UTType.png.identifier as CFString, 1, nil)
                    if destination == nil {
                        NSLog(
                            "Could not write file - destination returned from CGImageDestinationCreateWithURL was nil"
                        )
                        self.errorMessage(
                            message:
                                "Unfortunately, the image could not be saved to this location."
                        )
                    } else {
                        CGImageDestinationAddImage(destination!, cgImage!, nil)
                        CGImageDestinationFinalize(destination!)
                        NSLog("Image saved to: %@", fileURL.path)
                        self.sendNotification(title: "Image Captured", body: "Saved: \(filename)", sound: true)
                    }
                }
            } else {
                let popup: NSAlert = NSAlert()
                popup.messageText =
                    "Unfortunately, saving images is only supported in Mac OSX 10.12 (Sierra) and higher."
                popup.runModal()
            }
        }
    }

    @IBAction func captureVideo(_ sender: NSMenuItem) {
        guard let movieOutput = movieFileOutput else {
            errorMessage(message: "Video recording is not available. Please ensure a video device is selected.")
            return
        }
        
        if isRecording {
            // Stop recording
            movieOutput.stopRecording()
            NSLog("Stopping video recording...")
        } else {
            // Start recording
            guard let captureDir = getCaptureDirectory() else {
                errorMessage(message: "Unable to access the capture directory.\n\nPlease check your settings.")
                return
            }
            
            // Ensure capture session is running
            guard let session = captureSession else {
                errorMessage(message: "Capture session is not available.")
                return
            }
            
            if !session.isRunning {
                session.startRunning()
                // Give it a moment to establish connections
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.startVideoRecording(to: captureDir)
                }
            } else {
                startVideoRecording(to: captureDir)
            }
        }
    }
    
    private func startVideoRecording(to captureDir: URL) {
        guard let movieOutput = movieFileOutput else { return }
        
        // Generate unique filename
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: now)
        dateFormatter.dateFormat = "HH.mm.ss"
        let time = dateFormatter.string(from: now)
        
        let filename = String(format: "CapturePlay Video %@ at %@.mov", date, time)
        let fileURL = captureDir.appendingPathComponent(filename)
        
        // Configure recording settings for QuickTime compatibility
        configureRecordingSettings(movieOutput: movieOutput)
        
        // Check if file already exists and remove it
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
                NSLog("Removed existing file at: %@", fileURL.path)
            } catch {
                NSLog("ERROR: Could not remove existing file: %@", error.localizedDescription)
                errorMessage(message: "Cannot overwrite existing file: \(fileURL.lastPathComponent)")
                return
            }
        }
        
        // Check if directory is writable
        let directoryPath = fileURL.deletingLastPathComponent().path
        if !fileManager.isWritableFile(atPath: directoryPath) {
            NSLog("ERROR: Directory is not writable: %@", directoryPath)
            errorMessage(message: "Directory is not writable: \(directoryPath)")
            return
        }
        
        // Start recording
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        isRecording = true
        NSLog("Started video recording to: %@", fileURL.path)
        sendNotification(title: "Video Recording", body: "Recording started: \(filename)", sound: true)
    }
    
    private func configureRecordingSettings(movieOutput: AVCaptureMovieFileOutput) {
        // Configure audio settings for QuickTime compatibility (AAC, 256Kbps)
        if let audioConnection = movieOutput.connection(with: .audio) {
            // Get audio format from input if available
            var sampleRate: Double = 44100.0
            var channels: Int = 2
            
            if let audioInput = audioCaptureInput {
                let formatDesc = audioInput.device.activeFormat.formatDescription
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                if let asbd = asbd?.pointee {
                    sampleRate = Double(asbd.mSampleRate)
                    channels = Int(asbd.mChannelsPerFrame)
                }
            }
            
            // Set AAC audio settings for QuickTime compatibility
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 256000
            ]
            
            movieOutput.setOutputSettings(audioSettings, for: audioConnection)
            NSLog("Configured AAC audio: %.0f Hz, %d channels, 256Kbps", sampleRate, channels)
        } else {
            NSLog("Note: No audio connection available - video will be recorded without audio")
        }
        
        // Video will use source resolution automatically
        // No need to set custom video settings - system will use appropriate defaults
        if movieOutput.connection(with: .video) != nil {
            let videoDevice = input.device
            let dimensions = videoDevice.activeFormat.formatDescription.dimensions
            NSLog("Video recording at source resolution: %dx%d", dimensions.width, dimensions.height)
        } else {
            NSLog("ERROR: No video connection available")
        }
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        NSLog("Video recording started to: %@", fileURL.path)
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            
            if let error = error {
                let nsError = error as NSError
                NSLog("Video recording finished with error: %@", error.localizedDescription)
                NSLog("Error domain: %@, code: %ld", nsError.domain, nsError.code)
                
                // Check if file was created despite error
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: outputFileURL.path) {
                    let fileSize = (try? fileManager.attributesOfItem(atPath: outputFileURL.path)[.size] as? NSNumber)?.intValue ?? 0
                    NSLog("File exists at error location, size: %d bytes", fileSize)
                    if fileSize > 0 {
                        NSLog("File may be partially recorded, keeping it")
                        return
                    } else {
                        // Remove empty file
                        try? fileManager.removeItem(at: outputFileURL)
                        NSLog("Removed empty file")
                    }
                }
                
                self.errorMessage(message: "Video recording failed: \(error.localizedDescription)\n\nError code: \(nsError.code)")
            } else {
                // Verify file was created
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: outputFileURL.path) {
                    let fileSize = (try? fileManager.attributesOfItem(atPath: outputFileURL.path)[.size] as? NSNumber)?.intValue ?? 0
                    NSLog("Video recording finished successfully: %@ (size: %d bytes)", outputFileURL.path, fileSize)
                    let filename = outputFileURL.lastPathComponent
                    self.sendNotification(title: "Video Recording", body: "Recording saved: \(filename)", sound: true)
                } else {
                    NSLog("ERROR: Recording reported success but file does not exist: %@", outputFileURL.path)
                    self.errorMessage(message: "Recording completed but file was not created.")
                }
            }
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
        for menuItem: NSMenuItem in selectSourceMenu.submenu!.items {
            menuItem.state = NSControl.StateValue.off
        }
        sender.state = NSControl.StateValue.on

        self.startCaptureWithVideoDevice(defaultDevice: sender.representedObject as! Int)
    }

    // MARK: - Application Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        detectVideoDevices()
        startCaptureWithVideoDevice(defaultDevice: defaultDeviceIndex)
        usb.delegate = self
        setupFileMenu()
        applyDisplaySleepPreferenceFromSettings(force: true)
        observeWindowNotifications()
        requestAudioAccessIfNeeded()
        updateMuteMenuState()
        setupVolumeSlider()
        updateCaptureVideoMenuItemState()
        requestNotificationPermissions()
    }
    
    // MARK: - Notifications
    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    NSLog("Failed to request notification permissions: %@", error.localizedDescription)
                } else if granted {
                    NSLog("Notification permissions granted")
                } else {
                    NSLog("Notification permissions denied")
                }
            }
        }
    }
    
    private func sendNotification(title: String, body: String, sound: Bool = true) {
        let center = UNUserNotificationCenter.current()
        
        // Check authorization status first
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                NSLog("Notification authorization status: %d (not authorized)", settings.authorizationStatus.rawValue)
                return
            }
            
            DispatchQueue.main.async {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                if sound {
                    content.sound = .default
                }
                
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil // Deliver immediately
                )
                
                center.add(request) { error in
                    if let error = error {
                        NSLog("Failed to send notification: %@", error.localizedDescription)
                    } else {
                        NSLog("Notification sent successfully: %@ - %@", title, body)
                    }
                }
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
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

    private struct AudioOutputDeviceInfo {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    private func detectAudioDevices() {
        refreshAudioDeviceLists()
        ensureAudioSelections()
        buildAudioInputMenu()
        buildAudioOutputMenu()
        applyAudioConfiguration()
        updateMuteMenuState()
        updateVolumeSlider()
    }

    private func refreshAudioDeviceLists() {
        audioInputDevices = AVCaptureDevice.devices(for: .audio).sorted {
            $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending
        }
        audioOutputDevices = fetchAudioOutputDevices()
    }

    private func ensureAudioSelections() {
        let settings = QCSettingsManager.shared

        var preferredInputUID = settings.audioInputUID
        if preferredInputUID.isEmpty,
            let linkedAudio = currentVideoDevice?.linkedDevices.first(where: { $0.hasMediaType(.audio) })
        {
            preferredInputUID = linkedAudio.uniqueID
        }
        if preferredInputUID.isEmpty,
            let defaultInputUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeInput)
        {
            preferredInputUID = defaultInputUID
        }
        if preferredInputUID.isEmpty {
            preferredInputUID = audioInputDevices.first?.uniqueID ?? ""
        }
        if preferredInputUID != settings.audioInputUID {
            settings.setAudioInputUID(preferredInputUID)
        }
        if !preferredInputUID.isEmpty,
            !audioInputDevices.contains(where: { $0.uniqueID == preferredInputUID })
        {
            preferredInputUID = audioInputDevices.first?.uniqueID ?? ""
            settings.setAudioInputUID(preferredInputUID)
        }
        selectedAudioInputUID = preferredInputUID.isEmpty ? nil : preferredInputUID

        var preferredOutputUID = settings.audioOutputUID
        if preferredOutputUID.isEmpty,
            let defaultOutputUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeOutput)
        {
            preferredOutputUID = defaultOutputUID
        }
        if preferredOutputUID.isEmpty {
            preferredOutputUID = audioOutputDevices.first?.uid ?? ""
        }
        if preferredOutputUID != settings.audioOutputUID {
            settings.setAudioOutputUID(preferredOutputUID)
        }
        if !preferredOutputUID.isEmpty,
            !audioOutputDevices.contains(where: { $0.uid == preferredOutputUID })
        {
            preferredOutputUID = audioOutputDevices.first?.uid ?? ""
            settings.setAudioOutputUID(preferredOutputUID)
        }
        selectedAudioOutputUID = preferredOutputUID.isEmpty ? nil : preferredOutputUID
    }

    private func buildAudioInputMenu() {
        let menu = NSMenu()
        if audioInputDevices.isEmpty {
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
            for device in audioInputDevices {
                let item = NSMenuItem(
                    title: device.localizedName,
                    action: #selector(audioInputMenuChanged),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device.uniqueID
                item.state = (device.uniqueID == selectedAudioInputUID) ? .on : .off
                menu.addItem(item)
            }
        }
        selectAudioSourceMenu.submenu = menu
    }

    private func buildAudioOutputMenu() {
        let menu = NSMenu()
        if audioOutputDevices.isEmpty {
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
            for device in audioOutputDevices {
                let item = NSMenuItem(
                    title: device.name,
                    action: #selector(audioOutputMenuChanged),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device.uid
                item.state = (device.uid == selectedAudioOutputUID) ? .on : .off
                menu.addItem(item)
            }
        }
        selectAudioOutputMenu.submenu = menu
    }

    private func updateAudioInputMenuSelectionStates() {
        guard let menu = selectAudioSourceMenu.submenu else { return }
        for item in menu.items {
            guard let uid = item.representedObject as? String else {
                item.state = .off
                continue
            }
            item.state = (uid == selectedAudioInputUID) ? .on : .off
        }
    }

    private func updateAudioOutputMenuSelectionStates() {
        guard let menu = selectAudioOutputMenu.submenu else { return }
        for item in menu.items {
            guard let uid = item.representedObject as? String else {
                item.state = .off
                continue
            }
            item.state = (uid == selectedAudioOutputUID) ? .on : .off
        }
    }

    private func applyAudioConfiguration() {
        guard let session = captureSession else { return }

        session.beginConfiguration()

        let desiredInputUID = selectedAudioInputUID

        if let existingAudioInput = audioCaptureInput {
            if desiredInputUID == nil || existingAudioInput.device.uniqueID != desiredInputUID {
                session.removeInput(existingAudioInput)
                audioCaptureInput = nil
            }
        }

        if audioCaptureInput == nil,
            let audioUID = desiredInputUID,
            let device = audioInputDevices.first(where: { $0.uniqueID == audioUID })
        {
            do {
                let newAudioInput = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(newAudioInput) {
                    session.addInput(newAudioInput)
                    audioCaptureInput = newAudioInput
                }
            } catch {
                NSLog("Unable to add audio input %@: %@", device.localizedName, error.localizedDescription)
            }
        }

        if audioPreviewOutput == nil {
            let previewOutput = AVCaptureAudioPreviewOutput()
            let volume = QCSettingsManager.shared.audioVolume
            previewOutput.volume = QCSettingsManager.shared.isAudioMuted ? 0.0 : Float(volume)
            if session.canAddOutput(previewOutput) {
                session.addOutput(previewOutput)
                audioPreviewOutput = previewOutput
            }
        }

        session.commitConfiguration()

        updateAudioOutputRouting()

        if !session.isRunning {
            session.startRunning()
        }
        applyAudioMute()
    }

    private func updateAudioOutputRouting() {
        guard let preview = audioPreviewOutput else { return }
        let targetUID = selectedAudioOutputUID
        if preview.outputDeviceUniqueID != targetUID {
            preview.outputDeviceUniqueID = targetUID
        }
        applyAudioMute()
    }

    private func applyAudioMute() {
        let muted = QCSettingsManager.shared.isAudioMuted
        let volume = QCSettingsManager.shared.audioVolume
        if let preview = audioPreviewOutput {
            preview.volume = muted ? 0.0 : Float(volume)
        }
        muteAudioMenuItem?.state = muted ? .on : .off
        updateVolumeSlider()
    }

    private func applyAudioVolume() {
        let muted = QCSettingsManager.shared.isAudioMuted
        let volume = QCSettingsManager.shared.audioVolume
        if let preview = audioPreviewOutput {
            preview.volume = muted ? 0.0 : Float(volume)
        }
        updateVolumeSlider()
    }

    private func updateMuteMenuState() {
        muteAudioMenuItem?.state = QCSettingsManager.shared.isAudioMuted ? .on : .off
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
        QCSettingsManager.shared.setAudioVolume(volume)
        applyAudioVolume()
        QCSettingsManager.shared.saveSettings()
    }

    private func updateVolumeSlider() {
        volumeSlider?.doubleValue = Double(QCSettingsManager.shared.audioVolume)
    }

    private func fetchAudioOutputDevices() -> [AudioOutputDeviceInfo] {
        var results: [AudioOutputDeviceInfo] = []
        let deviceIDs = fetchAllAudioDeviceIDs()
        for deviceID in deviceIDs {
            if !audioDeviceHas(scope: kAudioDevicePropertyScopeOutput, deviceID: deviceID) {
                continue
            }
            guard
                let uid = copyAudioDevicePropertyString(
                    deviceID: deviceID,
                    selector: kAudioDevicePropertyDeviceUID,
                    scope: kAudioObjectPropertyScopeGlobal
                ),
                !uid.isEmpty
            else { continue }

            let name =
                copyAudioDevicePropertyString(
                    deviceID: deviceID,
                    selector: kAudioObjectPropertyName,
                    scope: kAudioObjectPropertyScopeGlobal
                )
                ?? copyAudioDevicePropertyString(
                    deviceID: deviceID,
                    selector: kAudioDevicePropertyDeviceNameCFString,
                    scope: kAudioObjectPropertyScopeGlobal
                )
                ?? "Audio Output"

            results.append(AudioOutputDeviceInfo(id: deviceID, uid: uid, name: name))
        }
        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func fetchAllAudioDeviceIDs() -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = deviceIDs.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }
        if status != noErr {
            return []
        }
        return deviceIDs
    }

    private func fetchDefaultAudioDeviceUID(for scope: AudioObjectPropertyScope) -> String? {
        let selector: AudioObjectPropertySelector
        switch scope {
        case kAudioDevicePropertyScopeInput:
            selector = kAudioHardwarePropertyDefaultInputDevice
        case kAudioDevicePropertyScopeOutput:
            selector = kAudioHardwarePropertyDefaultOutputDevice
        default:
            return nil
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        if status != noErr || deviceID == 0 {
            return nil
        }
        return copyAudioDevicePropertyString(
            deviceID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private func audioDeviceHas(scope: AudioObjectPropertyScope, deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        if status != noErr {
            return false
        }
        return dataSize > 0
    }

    private func copyAudioDevicePropertyString(
        deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfString: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &cfString
        )
        if status != noErr {
            return nil
        }
        return cfString as String?
    }

    private func updatePreferredAudioInputFromVideoIfNeeded(with device: AVCaptureDevice) {
        let settings = QCSettingsManager.shared
        guard settings.audioInputUID.isEmpty else { return }
        if let linkedAudio = device.linkedDevices.first(where: { $0.hasMediaType(.audio) }) {
            settings.setAudioInputUID(linkedAudio.uniqueID)
            selectedAudioInputUID = linkedAudio.uniqueID
        }
    }

    private func requestAudioAccessIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized, .restricted, .denied:
            detectAudioDevices()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.detectAudioDevices()
                }
            }
        @unknown default:
            detectAudioDevices()
        }
    }

    @objc private func audioInputMenuChanged(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        selectedAudioInputUID = uid
        QCSettingsManager.shared.setAudioInputUID(uid)
        updateAudioInputMenuSelectionStates()
        applyAudioConfiguration()
    }

    @objc private func audioOutputMenuChanged(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        selectedAudioOutputUID = uid
        QCSettingsManager.shared.setAudioOutputUID(uid)
        updateAudioOutputMenuSelectionStates()
        updateAudioOutputRouting()
    }

    @IBAction func toggleAudioMute(_ sender: NSMenuItem) {
        let newValue = !QCSettingsManager.shared.isAudioMuted
        QCSettingsManager.shared.setAudioMuted(newValue)
        updateMuteMenuState()
        applyAudioMute()
    }

    private func updateDisplaySleepMenuItemState() {
        displaySleepMenuItem?.state = isPreventingDisplaySleep ? .off : .on
    }
    
    private func updateCaptureVideoMenuItemState() {
        captureVideoMenuItem?.state = isRecording ? .on : .off
    }

    private func setDisplaySleepPrevention(
        enabled: Bool,
        persist: Bool,
        notifyOnFailure: Bool
    ) {
        if enabled {
            if isPreventingDisplaySleep {
                if persist {
                    QCSettingsManager.shared.setPreventDisplaySleep(true)
                }
                return
            }

            var assertionID: IOPMAssertionID = 0
            let reason = "CapturePlay Prevent Display Sleep" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )

            if result == kIOReturnSuccess {
                displaySleepAssertionID = assertionID
                isPreventingDisplaySleep = true
                if persist {
                    QCSettingsManager.shared.setPreventDisplaySleep(true)
                }
                sendNotification(title: "Display Sleep", body: "Display sleep prevention enabled", sound: false)
                return
            }

            NSLog("Failed to create display sleep assertion: \(result)")
            if notifyOnFailure {
                errorMessage(
                    message: "Unable to prevent the display from sleeping. Please try again."
                )
            }
            return
        }

        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
        let wasPreventing = isPreventingDisplaySleep
        isPreventingDisplaySleep = false
        if persist {
            QCSettingsManager.shared.setPreventDisplaySleep(false)
        }
        if wasPreventing {
            sendNotification(title: "Display Sleep", body: "Display sleep prevention disabled", sound: false)
        }
        if wasPreventing && notifyOnFailure {
            NSLog("Display sleep prevention disabled")
        }
    }

    private func applyDisplaySleepPreferenceFromSettings(force: Bool = false) {
        if isFullScreenActive && !force { return }
        let shouldPrevent = QCSettingsManager.shared.preventDisplaySleep
        setDisplaySleepPrevention(
            enabled: shouldPrevent,
            persist: false,
            notifyOnFailure: false
        )
    }

    private func observeWindowNotifications() {
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillEnterFullScreenNotification(_:)),
            name: NSWindow.willEnterFullScreenNotification,
            object: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEnterFullScreenNotification(_:)),
            name: NSWindow.didEnterFullScreenNotification,
            object: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillExitFullScreenNotification(_:)),
            name: NSWindow.willExitFullScreenNotification,
            object: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidExitFullScreenNotification(_:)),
            name: NSWindow.didExitFullScreenNotification,
            object: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMoveNotification(_:)),
            name: NSWindow.didMoveNotification,
            object: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResizeNotification(_:)),
            name: NSWindow.didResizeNotification,
            object: window)
    }

    private func enableGameMode() {
        guard gameModeActivity == nil else { return }
        let options: ProcessInfo.ActivityOptions = [
            .userInitiated,
            .latencyCritical
        ]
        gameModeActivity = ProcessInfo.processInfo.beginActivity(
            options: options,
            reason: "CapturePlay Full Screen Game Mode"
        )
    }

    private func disableGameMode() {
        if let activity = gameModeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            gameModeActivity = nil
        }
    }

    @IBAction func toggleDisplaySleep(_ sender: NSMenuItem) {
        setDisplaySleepPrevention(
            enabled: !isPreventingDisplaySleep,
            persist: true,
            notifyOnFailure: true
        )
    }

    private var preferencesDirectoryTextField: NSTextField?
    private var preferencesAlert: NSAlert?
    
    @IBAction func showPreferences(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Preferences"
        alert.informativeText = "Configure CapturePlay settings"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        // Create a custom view for preferences
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 120))
        
        // Checkbox for auto display sleep in full screen
        let displaySleepCheckbox = NSButton(checkboxWithTitle: "Automatically prevent display sleep during full screen", target: nil, action: nil)
        displaySleepCheckbox.frame = NSRect(x: 20, y: 80, width: 460, height: 20)
        displaySleepCheckbox.state = QCSettingsManager.shared.autoDisplaySleepInFullScreen ? .on : .off
        view.addSubview(displaySleepCheckbox)
        
        // Label and text field for capture directory
        let directoryLabel = NSTextField(labelWithString: "Capture Image Directory:")
        directoryLabel.frame = NSRect(x: 20, y: 50, width: 150, height: 17)
        view.addSubview(directoryLabel)
        
        let directoryTextField = NSTextField(frame: NSRect(x: 20, y: 20, width: 380, height: 22))
        var directoryPath = QCSettingsManager.shared.captureImageDirectory
        if directoryPath.isEmpty {
            let homePath = NSHomeDirectory()
            directoryPath = (homePath as NSString).appendingPathComponent("Pictures/CapturePlay")
        }
        directoryTextField.stringValue = directoryPath
        view.addSubview(directoryTextField)
        preferencesDirectoryTextField = directoryTextField
        preferencesAlert = alert
        
        let browseButton = NSButton(title: "Browse…", target: self, action: #selector(browseCaptureDirectory(_:)))
        browseButton.frame = NSRect(x: 410, y: 18, width: 70, height: 26)
        view.addSubview(browseButton)
        
        alert.accessoryView = view
        
        // Store references for the closure
        weak var weakTextField = directoryTextField
        weak var weakCheckbox = displaySleepCheckbox
        
        // Use beginSheetModal instead of runModal to allow nested dialogs
        alert.beginSheetModal(for: self.window!) { [weak self] response in
            self?.preferencesDirectoryTextField = nil
            self?.preferencesAlert = nil
            if response == .alertFirstButtonReturn {
                // OK clicked - save settings
                if let textField = weakTextField {
                    var path = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty {
                        // Always expand tilde paths when saving to avoid issues
                        if path.hasPrefix("~") {
                            path = self?.expandTildePath(path) ?? path
                        }
                        QCSettingsManager.shared.setCaptureImageDirectory(path)
                        NSLog("Saved capture directory: %@", path)
                    } else {
                        // Reset to default
                        QCSettingsManager.shared.setCaptureImageDirectory("")
                        NSLog("Reset capture directory to default")
                    }
                }
                if let checkbox = weakCheckbox {
                    QCSettingsManager.shared.setAutoDisplaySleepInFullScreen(checkbox.state == .on)
                }
                QCSettingsManager.shared.saveSettings()
            }
        }
    }
    
    @objc private func browseCaptureDirectory(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory for captured images"
        
        let settings = QCSettingsManager.shared
        var initialPath = settings.captureImageDirectory
        if initialPath.isEmpty {
            let homePath = NSHomeDirectory()
            initialPath = (homePath as NSString).appendingPathComponent("Pictures/CapturePlay")
        }
        panel.directoryURL = URL(fileURLWithPath: initialPath)
        
        // Use the alert's window if available, otherwise fall back to main window
        let parentWindow = preferencesAlert?.window ?? self.window!
        
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            if response == .OK, let url = panel.url {
                // Create security-scoped bookmark for persistent access
                do {
                    let bookmarkData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                    QCSettingsManager.shared.setCaptureImageDirectoryBookmark(bookmarkData)
                    QCSettingsManager.shared.setCaptureImageDirectory(url.path)
                    QCSettingsManager.shared.saveSettings()
                    NSLog("Saved security-scoped bookmark for directory: %@", url.path)
                } catch {
                    NSLog("WARNING: Failed to create security-scoped bookmark: %@", error.localizedDescription)
                    // Still save the path, but without bookmark
                    QCSettingsManager.shared.setCaptureImageDirectory(url.path)
                    QCSettingsManager.shared.setCaptureImageDirectoryBookmark(nil)
                    QCSettingsManager.shared.saveSettings()
                }
                
                if let textField = self?.preferencesDirectoryTextField {
                    textField.stringValue = url.path
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
        disableGameMode()
        NotificationCenter.default.removeObserver(self)
        updateWindowFrameSettings()
        QCSettingsManager.shared.saveSettings()
    }

    @objc private func windowWillEnterFullScreenNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        if !isFullScreenActive {
            displaySleepStateBeforeFullScreen = isPreventingDisplaySleep
        }
        isFullScreenActive = true
        displaySleepMenuItem?.isEnabled = false
        enableGameMode()
        if QCSettingsManager.shared.autoDisplaySleepInFullScreen {
            setDisplaySleepPrevention(
                enabled: true,
                persist: false,
                notifyOnFailure: false
            )
        }
    }

    @objc private func windowDidEnterFullScreenNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        if !cursorHiddenForFullScreen {
            NSCursor.hide()
            cursorHiddenForFullScreen = true
        }
    }

    @objc private func windowWillExitFullScreenNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        let previous =
            displaySleepStateBeforeFullScreen ?? QCSettingsManager.shared.preventDisplaySleep
        setDisplaySleepPrevention(
            enabled: previous,
            persist: true,
            notifyOnFailure: false
        )
    }

    @objc private func windowDidExitFullScreenNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        isFullScreenActive = false
        displaySleepStateBeforeFullScreen = nil
        displaySleepMenuItem?.isEnabled = true
        if cursorHiddenForFullScreen {
            NSCursor.unhide()
            cursorHiddenForFullScreen = false
        }
        disableGameMode()
        applyDisplaySleepPreferenceFromSettings(force: true)
        updateWindowFrameSettings()
    }

    @objc private func windowDidMoveNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }
        updateWindowFrameSettings()
    }

    @objc private func windowDidResizeNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }
        updateWindowFrameSettings()
    }

    private func updateWindowFrameSettings() {
        guard let window else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }
        let frame = window.frame
        let contentSize = window.contentLayoutRect.size
        QCSettingsManager.shared.setFrameProperties(
            x: Float(frame.minX),
            y: Float(frame.minY),
            width: Float(contentSize.width),
            height: Float(contentSize.height)
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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

