// Copyright H. Striepe - 2025

import AVFoundation
import Cocoa
import CoreImage
import CoreGraphics

// MARK: - QCWindowManagerDelegate Protocol
protocol QCWindowManagerDelegate: AnyObject {
    func windowManager(_ manager: QCWindowManager, willEnterFullScreen: Bool)
    func windowManager(_ manager: QCWindowManager, didEnterFullScreen: Bool)
    func windowManager(_ manager: QCWindowManager, willExitFullScreen: Bool)
    func windowManager(_ manager: QCWindowManager, didExitFullScreen: Bool)
    func windowManager(_ manager: QCWindowManager, didChangeFrame frame: NSRect)
    func windowManager(_ manager: QCWindowManager, needsSettingsUpdate: Void)
    func windowManager(_ manager: QCWindowManager, didChangeBorderless isBorderless: Bool)
    func windowManager(_ manager: QCWindowManager, didChangeRotation position: Int)
    func windowManager(_ manager: QCWindowManager, didChangeMirroring isMirrored: Bool)
    func windowManager(_ manager: QCWindowManager, didChangeUpsideDown isUpsideDown: Bool)
    func windowManager(_ manager: QCWindowManager, didChangeAspectRatioFixed isFixed: Bool)
    func windowManager(_ manager: QCWindowManager, didClickRecordingControl: Void)
}

// MARK: - QCWindowManager Class
class QCWindowManager: NSObject {
    
    // MARK: - Properties
    weak var delegate: QCWindowManagerDelegate?
    weak var window: NSWindow?
    weak var playerView: NSView?
    weak var captureLayer: AVCaptureVideoPreviewLayer?
    weak var videoInput: AVCaptureDeviceInput?
    
    private(set) var defaultBorderStyle: NSWindow.StyleMask = NSWindow.StyleMask.closable
    private(set) var windowTitle: String = "CapturePlay"
    private(set) var isFullScreenActive: Bool = false
    private(set) var cursorHiddenForFullScreen: Bool = false
    private var gameModeActivity: NSObjectProtocol?
    
    // Recording control overlay
    private var recordingControlButton: NSButton?
    private var recordingControlOverlay: NSWindow?
    private var blinkingTimer: Timer?
    private var isObservingWindowChanges = false
    private var isBlinkingVisible = true
    private var isShowingControl = false
    private var isCurrentlyRecording = false
    
    // Settings access (via delegate or direct)
    var isBorderless: Bool {
        get { QCSettingsManager.shared.isBorderless }
        set {
            QCSettingsManager.shared.setBorderless(newValue)
            delegate?.windowManager(self, didChangeBorderless: newValue)
        }
    }
    
    var position: Int {
        get { QCSettingsManager.shared.position }
        set {
            QCSettingsManager.shared.setPosition(newValue)
            setRotation(newValue)
            delegate?.windowManager(self, didChangeRotation: newValue)
        }
    }
    
    var isMirrored: Bool {
        get { QCSettingsManager.shared.isMirrored }
        set {
            QCSettingsManager.shared.setMirrored(newValue)
            applyMirroring()
            delegate?.windowManager(self, didChangeMirroring: newValue)
        }
    }
    
    var isUpsideDown: Bool {
        get { QCSettingsManager.shared.isUpsideDown }
        set {
            QCSettingsManager.shared.setUpsideDown(newValue)
            setRotation(position)
            delegate?.windowManager(self, didChangeUpsideDown: newValue)
        }
    }
    
    var isAspectRatioFixed: Bool {
        get { QCSettingsManager.shared.isAspectRatioFixed }
        set {
            QCSettingsManager.shared.setAspectRatioFixed(newValue)
            fixAspectRatio()
            delegate?.windowManager(self, didChangeAspectRatioFixed: newValue)
        }
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
    }
    
    // MARK: - Window Appearance Configuration
    func configureTranslucentTitleBar() {
        guard let window = window else { return }
        
        // Configure window for translucent title bar like QuickTime Player
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // Enable full-size content view (content extends into title bar area)
        window.styleMask.insert(.fullSizeContentView)
        
        // Set appearance to dark to ensure white title text over video content
        window.appearance = NSAppearance(named: .darkAqua)
        
        // Set up mouse tracking for title bar visibility
        setupTitleBarMouseTracking()
        
    }
    
    private func setupTitleBarMouseTracking() {
        guard let window = window, let contentView = window.contentView else { return }
        
        // Create a custom tracking view that covers the entire content area
        let trackingView = TitleBarTrackingView(windowManager: self)
        trackingView.frame = contentView.bounds
        trackingView.autoresizingMask = [.width, .height]
        
        // Insert the tracking view as the bottom-most subview
        contentView.addSubview(trackingView, positioned: .below, relativeTo: nil)
        
        // Initially hide the title
        window.titleVisibility = .hidden
        hideTitleBar()
    }
    
    // MARK: - Window Border Management
    func addBorder() {
        guard let window = window else { return }
        window.styleMask = defaultBorderStyle
        window.title = windowTitle
        window.level = convertToNSWindowLevel(Int(CGWindowLevelForKey(.normalWindow)))
        window.isMovableByWindowBackground = false
        
        // Apply translucent title bar configuration
        configureTranslucentTitleBar()
    }
    
    func removeBorder() {
        guard let window = window else { return }
        defaultBorderStyle = window.styleMask
        window.styleMask = [NSWindow.StyleMask.borderless, NSWindow.StyleMask.resizable]
        window.level = convertToNSWindowLevel(Int(CGWindowLevelForKey(.maximumWindow)))
        window.isMovableByWindowBackground = true
    }
    
    func toggleBorderless() {
        guard let window = window else { return }
        if window.styleMask.contains(.fullScreen) {
            NSLog("Ignoring borderless command as window is full screen")
            return
        }
        isBorderless = !isBorderless
        if isBorderless {
            removeBorder()
        } else {
            addBorder()
        }
        fixAspectRatio()
    }
    
    // MARK: - Window Title Management
    func setWindowTitle(_ title: String) {
        windowTitle = title
        window?.title = title
    }
    
    // MARK: - Rotation and Mirroring
    func setRotation(_ position: Int) {
        guard let captureLayer = captureLayer else { return }
        switch position {
        case 1:
            if !isUpsideDown {
                captureLayer.connection?.videoOrientation = .landscapeLeft
            } else {
                captureLayer.connection?.videoOrientation = .landscapeRight
            }
        case 2:
            if !isUpsideDown {
                captureLayer.connection?.videoOrientation = .portraitUpsideDown
            } else {
                captureLayer.connection?.videoOrientation = .portrait
            }
        case 3:
            if !isUpsideDown {
                captureLayer.connection?.videoOrientation = .landscapeRight
            } else {
                captureLayer.connection?.videoOrientation = .landscapeLeft
            }
        case 0:
            if !isUpsideDown {
                captureLayer.connection?.videoOrientation = .portrait
            } else {
                captureLayer.connection?.videoOrientation = .portraitUpsideDown
            }
        default:
            break
        }
    }
    
    func applyMirroring() {
        guard let captureLayer = captureLayer else { return }
        captureLayer.connection?.isVideoMirrored = isMirrored
    }
    
    // MARK: - Color Correction
    func applyColorCorrection(brightness: Float, contrast: Float, hue: Float) {
        guard let playerView = playerView, let layer = playerView.layer else { return }
        
        // Enable layer-backed rendering for filters
        playerView.wantsLayer = true
        
        // Create composite filter combining brightness, contrast, and hue
        var filters: [CIFilter] = []
        
        // Brightness and Contrast filter
        if brightness != 0.0 || contrast != 1.0 {
            if let brightnessFilter = CIFilter(name: "CIColorControls") {
                brightnessFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
                brightnessFilter.setValue(contrast, forKey: kCIInputContrastKey)
                filters.append(brightnessFilter)
            }
        }
        
        // Hue adjustment filter
        if hue != 0.0 {
            if let hueFilter = CIFilter(name: "CIHueAdjust") {
                hueFilter.setValue(hue * .pi / 180.0, forKey: kCIInputAngleKey) // Convert degrees to radians
                filters.append(hueFilter)
            }
        }
        
        // Apply filters to the layer
        layer.filters = filters.isEmpty ? nil : filters
    }
    
    func swapWH() {
        guard let window = window else { return }
        var currentSize: CGSize = window.contentLayoutRect.size
        swap(&currentSize.height, &currentSize.width)
        window.setContentSize(currentSize)
    }
    
    // MARK: - Recording Control Overlay
    func showRecordingControl() {
        guard let window = window else { return }
        
        // Prevent re-entrant calls
        guard !isShowingControl else { return }
        
        // If control already exists, just ensure it's visible (if appropriate)
        if recordingControlOverlay != nil && recordingControlButton != nil {
            updateRecordingControlVisibility()
            return
        }
        
        isShowingControl = true
        defer { isShowingControl = false }
        
        // Remove existing overlay if any (shouldn't be necessary but safe)
        hideRecordingControl()
        
        // Create overlay window
        let buttonSize: CGFloat = 30
        let margin: CGFloat = 20
        let overlayWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: buttonSize, height: buttonSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = false
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        overlayWindow.isExcludedFromWindowsMenu = true
        // Exclude from screen recording by setting sharing type (macOS 10.15+)
        if #available(macOS 10.15, *) {
            overlayWindow.sharingType = .none
        }
        // Set window level relative to main window (floating above it when visible)
        // This ensures it doesn't float above other apps when the window is obscured
        overlayWindow.level = .floating
        
        // Create button
        let button = NSButton()
        button.frame = NSRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
        button.isBordered = false
        button.title = ""
        button.target = self
        button.action = #selector(recordingControlClicked(_:))
        updateRecordingControlAppearance(button: button, isRecording: false)
        
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: buttonSize, height: buttonSize))
        contentView.addSubview(button)
        overlayWindow.contentView = contentView
        
        // Store references before positioning
        recordingControlOverlay = overlayWindow
        recordingControlButton = button
        
        // Position at bottom right of main window (defer if window not ready)
        if window.isVisible || window.isKeyWindow {
            updateRecordingControlPosition()
        } else {
            // Delay positioning until window is ready
            DispatchQueue.main.async { [weak self] in
                self?.updateRecordingControlPosition()
            }
        }
        
        // Order overlay relative to main window
        overlayWindow.order(.above, relativeTo: window.windowNumber)
        
        // Update visibility based on app/window state
        updateRecordingControlVisibility()
        
        // Observe window frame changes and app/window state (only add once)
        if !isObservingWindowChanges {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowFrameChanged(_:)),
                name: NSWindow.didMoveNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowFrameChanged(_:)),
                name: NSWindow.didResizeNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appDidBecomeActive(_:)),
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appDidResignActive(_:)),
                name: NSApplication.didResignActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey(_:)),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeMain(_:)),
                name: NSWindow.didBecomeMainNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidResignMain(_:)),
                name: NSWindow.didResignMainNotification,
                object: window
            )
            isObservingWindowChanges = true
        }
    }
    
    func hideRecordingControl() {
        // Ensure we're on the main thread for UI operations
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.hideRecordingControl()
            }
            return
        }
        
        // Prevent hide while showing
        guard !isShowingControl else { return }
        
        // Stop blinking and clean up timer first (safely)
        stopBlinking()
        if blinkingTimer != nil {
            blinkingTimer?.invalidate()
            blinkingTimer = nil
        }
        
        // Get references before clearing
        let overlay = recordingControlOverlay
        let button = recordingControlButton
        let observing = isObservingWindowChanges
        let mainWindow = window
        
        // Clear button target/action first to prevent any further callbacks
        if let button = button {
            button.target = nil
            button.action = nil
        }
        
        // Clear references immediately to prevent re-entrancy
        recordingControlOverlay = nil
        recordingControlButton = nil
        
        // Remove observers if we were observing (before closing window)
        if observing {
            if let window = mainWindow {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: window)
                NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: window)
                NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
                NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
                NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeMainNotification, object: window)
                NotificationCenter.default.removeObserver(self, name: NSWindow.didResignMainNotification, object: window)
            }
            NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
            isObservingWindowChanges = false
        }
        
        // Close overlay window last - do it safely
        if let overlay = overlay {
            overlay.close()
        }
    }
    
    func updateRecordingControlState(isRecording: Bool) {
        // Update recording state
        isCurrentlyRecording = isRecording
        
        // Ensure we're on the main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let button = self.recordingControlButton,
                  let overlay = self.recordingControlOverlay else { return }
            
            self.updateRecordingControlAppearance(button: button, isRecording: isRecording)
            
            if isRecording {
                self.startBlinking()
            } else {
                self.stopBlinking()
            }
            
            // Update visibility when recording state changes
            self.updateRecordingControlVisibility()
        }
    }
    
    private func updateRecordingControlAppearance(button: NSButton, isRecording: Bool) {
        let buttonSize: CGFloat = 30
        let borderInset: CGFloat = 2
        let borderWidth: CGFloat = 2
        
        button.wantsLayer = true
        
        // Button frame is already set, just update corner radius
        let cornerRadius: CGFloat
        if isRecording {
            // Square button when recording
            cornerRadius = 4
        } else {
            // Round button when not recording
            cornerRadius = buttonSize / 2
        }
        button.layer?.cornerRadius = cornerRadius
        button.layer?.backgroundColor = NSColor.red.cgColor
        button.title = ""
        
        // Remove existing border layer if present
        button.layer?.sublayers?.removeAll { $0.name == "innerBorder" }
        
        // Add 2-pixel border line 2 pixels inside the button edge
        let borderLayer = CALayer()
        borderLayer.name = "innerBorder"
        let borderSize = buttonSize - (borderInset * 2)
        borderLayer.frame = CGRect(x: borderInset, y: borderInset, width: borderSize, height: borderSize)
        borderLayer.cornerRadius = isRecording ? (cornerRadius - borderInset) : (borderSize / 2)
        borderLayer.borderWidth = borderWidth
        borderLayer.borderColor = NSColor.white.cgColor
        borderLayer.backgroundColor = NSColor.clear.cgColor
        button.layer?.addSublayer(borderLayer)
        
        // Update tooltip
        button.toolTip = isRecording ? "Stop Recording" : "Start Recording"
    }
    
    private func updateRecordingControlPosition() {
        guard let window = window, let overlay = recordingControlOverlay else { return }
        guard window.isVisible || window.isKeyWindow else { return }
        
        let buttonSize: CGFloat = 30
        let margin: CGFloat = 20
        let windowFrame = window.frame
        
        // Safely get content layout rect, fallback to frame if not available
        let contentRect: NSRect
        if windowFrame.width > 0 && windowFrame.height > 0 {
            contentRect = window.contentLayoutRect
            // Validate content rect is reasonable
            guard contentRect.width > 0 && contentRect.height > 0 else { return }
        } else {
            return
        }
        
        // Calculate position at bottom right of content area
        let overlayX = windowFrame.minX + contentRect.maxX - buttonSize - margin
        let overlayY = windowFrame.minY + contentRect.minY + margin
        
        overlay.setFrameOrigin(NSPoint(x: overlayX, y: overlayY))
    }
    
    @objc private func windowFrameChanged(_ notification: Notification) {
        guard recordingControlOverlay != nil else { return }
        updateRecordingControlPosition()
        updateRecordingControlVisibility()
    }
    
    @objc private func appDidBecomeActive(_ notification: Notification) {
        updateRecordingControlVisibility()
    }
    
    @objc private func appDidResignActive(_ notification: Notification) {
        updateRecordingControlVisibility()
    }
    
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        updateRecordingControlVisibility()
    }
    
    @objc private func windowDidResignKey(_ notification: Notification) {
        updateRecordingControlVisibility()
    }
    
    @objc private func windowDidBecomeMain(_ notification: Notification) {
        updateRecordingControlVisibility()
    }
    
    @objc private func windowDidResignMain(_ notification: Notification) {
        updateRecordingControlVisibility()
    }
    
    private func updateRecordingControlVisibility() {
        guard let overlay = recordingControlOverlay,
              let mainWindow = window else { return }
        
        // Check if app is active and window is key/main
        let appIsActive = NSApplication.shared.isActive
        let windowIsKey = mainWindow.isKeyWindow
        let windowIsMain = mainWindow.isMainWindow
        let windowIsVisible = mainWindow.isVisible
        
        // Check if title bar is currently visible
        let titleBarIsVisible = mainWindow.titleVisibility == .visible
        
        // Always show controls while recording, otherwise follow title bar visibility
        let shouldBeVisible = appIsActive && windowIsVisible && (windowIsKey || windowIsMain) && (isCurrentlyRecording || titleBarIsVisible)
        
        if shouldBeVisible {
            overlay.orderFront(nil)
            // Ensure it's above the main window
            overlay.order(.above, relativeTo: mainWindow.windowNumber)
        } else {
            overlay.orderOut(nil)
        }
    }
    
    @objc private func recordingControlClicked(_ sender: NSButton) {
        // Normal click - toggle recording
        delegate?.windowManager(self, didClickRecordingControl: ())
    }
    
    private func startBlinking() {
        stopBlinking()
        
        guard recordingControlOverlay != nil else { return }
        
        isBlinkingVisible = true
        // Create timer on main run loop to ensure thread safety
        blinkingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self,
                  let overlay = self.recordingControlOverlay else {
                timer.invalidate()
                return
            }
            // Toggle visibility state
            self.isBlinkingVisible.toggle()
            // Update UI on main thread
            DispatchQueue.main.async {
                overlay.alphaValue = self.isBlinkingVisible ? 1.0 : 0.3
            }
        }
    }
    
    private func stopBlinking() {
        blinkingTimer?.invalidate()
        blinkingTimer = nil
        recordingControlOverlay?.alphaValue = 1.0
    }
    
    func rotateLeft() {
        position = position - 1
        if position == -1 { position = 3 }
        swapWH()
        setRotation(position)
        delegate?.windowManager(self, needsSettingsUpdate: ())
    }
    
    func rotateRight() {
        position = position + 1
        if position == 4 { position = 0 }
        swapWH()
        setRotation(position)
        delegate?.windowManager(self, needsSettingsUpdate: ())
    }
    
    func toggleMirrorHorizontally() {
        isMirrored = !isMirrored
        applyMirroring()
        delegate?.windowManager(self, needsSettingsUpdate: ())
    }
    
    func toggleMirrorVertically() {
        isUpsideDown = !isUpsideDown
        setRotation(position)
        delegate?.windowManager(self, needsSettingsUpdate: ())
    }
    
    func isLandscape() -> Bool {
        return position % 2 == 0
    }
    
    // MARK: - Aspect Ratio Management
    func fixAspectRatio() {
        guard let window = window, let input = videoInput else { return }
        if isAspectRatioFixed, #available(OSX 10.15, *) {
            let height: Int32 = input.device.activeFormat.formatDescription.dimensions.height
            let width: Int32 = input.device.activeFormat.formatDescription.dimensions.width
            let size: NSSize =
                isLandscape()
                ? NSMakeSize(CGFloat(width), CGFloat(height))
                : NSMakeSize(CGFloat(height), CGFloat(width))
            window.contentAspectRatio = size
            
            let ratio: CGFloat = CGFloat(Float(width) / Float(height))
            var currentSize: CGSize = window.contentLayoutRect.size
            if isLandscape() {
                currentSize.height = currentSize.width / ratio
            } else {
                currentSize.height = currentSize.width * ratio
            }
            NSLog(
                "fixAspectRatio : %f - %d,%d - %f,%f - %f,%f", ratio, width, height, size.width,
                size.height, currentSize.width, currentSize.height)
            window.setContentSize(currentSize)
        } else {
            window.contentResizeIncrements = NSMakeSize(1.0, 1.0)
        }
    }
    
    func toggleFixAspectRatio() {
        isAspectRatioFixed = !isAspectRatioFixed
        fixAspectRatio()
        delegate?.windowManager(self, needsSettingsUpdate: ())
    }
    
    func fitToActualSize() {
        guard let window = window, let input = videoInput else { return }
        if #available(OSX 10.15, *) {
            let height: Int32 = input.device.activeFormat.formatDescription.dimensions.height
            let width: Int32 = input.device.activeFormat.formatDescription.dimensions.width
            var currentSize: CGSize = window.contentLayoutRect.size
            currentSize.width = CGFloat(isLandscape() ? width : height)
            currentSize.height = CGFloat(isLandscape() ? height : width)
            window.setContentSize(currentSize)
        }
    }
    
    // MARK: - Full Screen Management
    func enterFullScreen() {
        playerView?.window?.toggleFullScreen(self)
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
    
    private func handleWillEnterFullScreen() {
        guard !isFullScreenActive else { return }
        isFullScreenActive = true
        delegate?.windowManager(self, willEnterFullScreen: true)
        enableGameMode()
    }
    
    private func handleDidEnterFullScreen() {
        if !cursorHiddenForFullScreen {
            NSCursor.hide()
            cursorHiddenForFullScreen = true
        }
        delegate?.windowManager(self, didEnterFullScreen: true)
    }
    
    private func handleWillExitFullScreen() {
        delegate?.windowManager(self, willExitFullScreen: true)
    }
    
    private func handleDidExitFullScreen() {
        isFullScreenActive = false
        if cursorHiddenForFullScreen {
            NSCursor.unhide()
            cursorHiddenForFullScreen = false
        }
        disableGameMode()
        delegate?.windowManager(self, didExitFullScreen: true)
    }
    
    // MARK: - Window Notifications
    func observeWindowNotifications() {
        guard let window = window else { return }
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
    
    @objc private func windowWillEnterFullScreenNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        handleWillEnterFullScreen()
    }
    
    @objc private func windowDidEnterFullScreenNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        handleDidEnterFullScreen()
    }
    
    @objc private func windowWillExitFullScreenNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        handleWillExitFullScreen()
    }
    
    @objc private func windowDidExitFullScreenNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        handleDidExitFullScreen()
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
    
    // MARK: - Window Frame Persistence
    func updateWindowFrameSettings() {
        guard let window = window else { return }
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
    
    func loadWindowFrame() {
        guard let window = window else { return }
        let savedW = QCSettingsManager.shared.frameWidth
        let savedH = QCSettingsManager.shared.frameHeight
        if 100 < savedW && 100 < savedH {
            let savedX = QCSettingsManager.shared.frameX
            let savedY = QCSettingsManager.shared.frameY
            NSLog("loaded : x:%f,y:%f,w:%f,h:%f", savedX, savedY, savedW, savedH)
            var currentSize: CGSize = window.contentLayoutRect.size
            currentSize.width = CGFloat(savedW)
            currentSize.height = CGFloat(savedH)
            window.setContentSize(currentSize)
            window.setFrameOrigin(NSPoint(x: CGFloat(savedX), y: CGFloat(savedY)))
        }
    }
    
    // MARK: - Helper Functions
    private func convertToNSWindowLevel(_ input: Int) -> NSWindow.Level {
        NSWindow.Level(rawValue: input)
    }
    
    // MARK: - Mouse Tracking for Title Bar
    func handleMouseEntered() {
        showTitleBarTemporarily()
    }
    
    func handleMouseExited() {
        hideTitleBarAfterDelay()
    }
    
    func handleMouseMoved(at location: NSPoint) {
        // Check if mouse is in title bar area (top 28 pixels)
        guard let window = window else { return }
        let titleBarHeight: CGFloat = 28
        let windowHeight = window.contentView?.bounds.height ?? 0
        
        if location.y > windowHeight - titleBarHeight {
            showTitleBarTemporarily()
        } else {
            hideTitleBarAfterDelay()
        }
    }
    
    private func showTitleBarTemporarily() {
        guard let window = window else { return }
        
        // Cancel any pending hide operations
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideTitleBar), object: nil)
        
        // Show title and window controls
        window.titleVisibility = .visible
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        
        // Update recording control visibility when title bar is shown
        updateRecordingControlVisibility()
    }
    
    private func hideTitleBarAfterDelay() {
        // Cancel any previous hide requests
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideTitleBar), object: nil)
        
        // Hide title bar after 2 seconds of no mouse activity
        perform(#selector(hideTitleBar), with: nil, afterDelay: 2.0)
    }
    
    @objc private func hideTitleBar() {
        guard let window = window else { return }
        
        // Hide title and window controls
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Update recording control visibility when title bar is hidden
        updateRecordingControlVisibility()
    }
    
    deinit {
        // Cancel any pending operations
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        // Clean up any remaining observers
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Title Bar Tracking View
class TitleBarTrackingView: NSView {
    weak var windowManager: QCWindowManager?
    
    init(windowManager: QCWindowManager) {
        self.windowManager = windowManager
        super.init(frame: NSRect.zero)
        
        // Create tracking area for mouse events
        updateTrackingAreas()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove existing tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }
        
        // Add new tracking area covering the entire view
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        windowManager?.handleMouseEntered()
    }
    
    override func mouseExited(with event: NSEvent) {
        windowManager?.handleMouseExited()
    }
    
    override func mouseMoved(with event: NSEvent) {
        let location = event.locationInWindow
        windowManager?.handleMouseMoved(at: location)
    }
    
    // Make view transparent to clicks so it doesn't interfere with content
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

