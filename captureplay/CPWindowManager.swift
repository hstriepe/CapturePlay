// Copyright H. Striepe ©2025

import AVFoundation
import Cocoa
import CoreImage
import CoreGraphics

// MARK: - CPWindowManagerDelegate Protocol
protocol CPWindowManagerDelegate: AnyObject {
    func windowManager(_ manager: CPWindowManager, willEnterFullScreen: Bool)
    func windowManager(_ manager: CPWindowManager, didEnterFullScreen: Bool)
    func windowManager(_ manager: CPWindowManager, willExitFullScreen: Bool)
    func windowManager(_ manager: CPWindowManager, didExitFullScreen: Bool)
    func windowManager(_ manager: CPWindowManager, didChangeFrame frame: NSRect)
    func windowManager(_ manager: CPWindowManager, needsSettingsUpdate: Void)
    func windowManager(_ manager: CPWindowManager, didChangeBorderless isBorderless: Bool)
    func windowManager(_ manager: CPWindowManager, didChangeRotation position: Int)
    func windowManager(_ manager: CPWindowManager, didChangeMirroring isMirrored: Bool)
    func windowManager(_ manager: CPWindowManager, didChangeUpsideDown isUpsideDown: Bool)
    func windowManager(_ manager: CPWindowManager, didChangeAspectRatioFixed isFixed: Bool)
    func windowManager(_ manager: CPWindowManager, didClickRecordingControl: Void)
}

// MARK: - CPWindowManager Class
class CPWindowManager: NSObject {
    
    // MARK: - Properties
    weak var delegate: CPWindowManagerDelegate?
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
    private var hideTimer: Timer?
    private var isObservingWindowChanges = false
    private var isBlinkingVisible = true
    private var isShowingControl = false
    private var isCurrentlyRecording = false
    private var hasEverShownControl = false // Track if overlay has ever been shown
    private var isInPostRecordingPeriod = false // Track if we're in the 30-second post-recording period
    
    // Settings access (via delegate or direct)
    var isBorderless: Bool {
        get { CPSettingsManager.shared.isBorderless }
        set {
            CPSettingsManager.shared.setBorderless(newValue)
            delegate?.windowManager(self, didChangeBorderless: newValue)
        }
    }
    
    var position: Int {
        get { CPSettingsManager.shared.position }
        set {
            CPSettingsManager.shared.setPosition(newValue)
            setRotation(newValue)
            delegate?.windowManager(self, didChangeRotation: newValue)
        }
    }
    
    var isMirrored: Bool {
        get { CPSettingsManager.shared.isMirrored }
        set {
            CPSettingsManager.shared.setMirrored(newValue)
            applyMirroring()
            delegate?.windowManager(self, didChangeMirroring: newValue)
        }
    }
    
    var isUpsideDown: Bool {
        get { CPSettingsManager.shared.isUpsideDown }
        set {
            CPSettingsManager.shared.setUpsideDown(newValue)
            setRotation(position)
            delegate?.windowManager(self, didChangeUpsideDown: newValue)
        }
    }
    
    var isAspectRatioFixed: Bool {
        get { CPSettingsManager.shared.isAspectRatioFixed }
        set {
            CPSettingsManager.shared.setAspectRatioFixed(newValue)
            fixAspectRatio()
            delegate?.windowManager(self, didChangeAspectRatioFixed: newValue)
        }
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
    }
    
    // Pre-create the overlay window to prevent flash on first use
    func prepareRecordingControl() {
        guard let window = window else { return }
        guard recordingControlOverlay == nil else { return } // Already created
        
        // Create overlay window off-screen
        let buttonSize: CGFloat = 30
        let overlayWindow = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: buttonSize, height: buttonSize),
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
        if #available(macOS 10.15, *) {
            overlayWindow.sharingType = .none
        }
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
        
        // Store references
        recordingControlOverlay = overlayWindow
        recordingControlButton = button
        
        // Keep it hidden and off-screen until needed
        // Don't warm it up - that can cause flashing
        overlayWindow.orderOut(nil)
        
        // Make overlay a child window so it moves smoothly with the main window
        // Defer this until window is ready to avoid crashes
        DispatchQueue.main.async { [weak self, weak overlayWindow] in
            guard let self = self,
                  let overlay = overlayWindow,
                  let parentWindow = self.window,
                  parentWindow.isVisible || parentWindow.isOnActiveSpace else {
                return
            }
            // Only add as child window if parent is ready
            if let childWindows = parentWindow.childWindows, !childWindows.contains(overlay) {
                parentWindow.addChildWindow(overlay, ordered: .above)
            } else if parentWindow.childWindows == nil {
                parentWindow.addChildWindow(overlay, ordered: .above)
            }
        }
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
        guard let captureLayer = captureLayer else {
            // Layer not ready yet - will be applied when layer is set
            NSLog("setRotation called but captureLayer is nil (position: %d)", position)
            return
        }
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
    
    // MARK: - Rendering Optimizations
    private func optimizeViewForSmoothRendering(previewView: NSView) {
        // Configure view for optimal video rendering performance
        previewView.wantsLayer = true
        
        guard let layer = previewView.layer else { return }
        
        // Enable hardware acceleration
        layer.drawsAsynchronously = true // Use background thread for drawing
        
        // Optimize for video content
        layer.isOpaque = true // No transparency needed for video
        layer.contentsGravity = .resizeAspectFill
        
        // Reduce compositing overhead
        layer.shouldRasterize = false // Don't rasterize video layers
        
        // Use optimal pixel format for video
        if #available(macOS 10.15, *) {
            layer.contentsFormat = .RGBA8Uint
        }
        
        // Disable unnecessary effects that can cause frame drops
        layer.shadowOpacity = 0.0
        layer.cornerRadius = 0.0
        layer.borderWidth = 0.0
    }
    
    // MARK: - Color Correction
    func applyColorCorrection(brightness: Float, contrast: Float, hue: Float) {
        guard let playerView = playerView, let layer = playerView.layer else { return }
        
        // Performance optimization: Skip filter application if all values are at defaults
        // This avoids expensive CoreImage processing on every frame when no correction is needed
        if brightness == 0.0 && contrast == 1.0 && hue == 0.0 {
            // Remove filters if they exist (for when user resets to defaults)
            if layer.filters != nil && !layer.filters!.isEmpty {
                layer.filters = nil
            }
            return
        }
        
        // Enable layer-backed rendering for filters
        playerView.wantsLayer = true
        
        // Create composite filter combining brightness, contrast, and hue
        var filters: [CIFilter] = []
        
        // Brightness and Contrast filter
        if brightness != 0.0 || contrast != 1.0 {
            if let brightnessFilter = CIFilter(name: "CIColorControls") {
                brightnessFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
                brightnessFilter.setValue(contrast, forKey: kCIInputContrastKey)
                // CoreImage filters are automatically GPU-accelerated
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
        // CoreImage filters are GPU-accelerated, but still have overhead
        // Only apply when actually needed (checked above)
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
        
        // Ensure overlay is pre-created (should already be done, but be safe)
        if recordingControlOverlay == nil {
            prepareRecordingControl()
        }
        
        // If control already exists, just ensure it's visible (if appropriate)
        if recordingControlOverlay != nil && recordingControlButton != nil {
            updateRecordingControlVisibility()
            return
        }
        
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
        
        // Batch window updates to prevent screen flash
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        if let mainWindow = window {
            mainWindow.disableScreenUpdatesUntilFlush()
        }
        
        // Stop blinking and clean up timers first (safely)
        stopBlinking()
        if blinkingTimer != nil {
            blinkingTimer?.invalidate()
            blinkingTimer = nil
        }
        // Cancel hide timer
        hideTimer?.invalidate()
        hideTimer = nil
        
        // Get references before clearing
        let overlay = recordingControlOverlay
        let button = recordingControlButton
        let observing = isObservingWindowChanges
        let mainWindow = window
        
        // Hide overlay before closing to prevent flash
        overlay?.orderOut(nil)
        
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
        
        // Remove child window relationship before closing
        if let overlay = overlay, let mainWindow = mainWindow {
            mainWindow.removeChildWindow(overlay)
        }
        
        // Close overlay window last - do it safely
        if let overlay = overlay {
            overlay.close()
        }
        
        // Flush all window updates at once to prevent flash
        NSAnimationContext.endGrouping()
        mainWindow?.flush()
    }
    
    func updateRecordingControlState(isRecording: Bool) {
        // Update recording state
        isCurrentlyRecording = isRecording
        
        // Ensure we're on the main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let button = self.recordingControlButton,
                  self.recordingControlOverlay != nil else { return }
            
            // Batch window updates to prevent screen flash
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            if let mainWindow = self.window {
                mainWindow.disableScreenUpdatesUntilFlush()
            }
            
            self.updateRecordingControlAppearance(button: button, isRecording: isRecording)
            
            if isRecording {
                // Mark that control has been used (first recording)
                self.hasEverShownControl = true
                // Cancel any pending hide timer and end post-recording period
                self.hideTimer?.invalidate()
                self.hideTimer = nil
                self.isInPostRecordingPeriod = false
                self.startBlinking()
            } else {
                self.stopBlinking()
                // Schedule hide after 30 seconds when recording stops
                self.scheduleHideAfterDelay()
            }
            
            // Update visibility when recording state changes
            self.updateRecordingControlVisibility()
            
            // Flush all window updates at once to prevent flash
            NSAnimationContext.endGrouping()
            self.window?.flush()
        }
    }
    
    private func scheduleHideAfterDelay() {
        // Cancel any existing hide timer
        hideTimer?.invalidate()
        
        // Mark that we're in the post-recording period
        isInPostRecordingPeriod = true
        
        // Schedule hide after 30 seconds
        hideTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Only hide if not currently recording
            if !self.isCurrentlyRecording {
                // End the post-recording period
                self.isInPostRecordingPeriod = false
                // Update visibility (will hide if title bar is not visible)
                self.updateRecordingControlVisibility()
            }
        }
        
        // Ensure control is visible during post-recording period
        updateRecordingControlVisibility()
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
        
        // Safely get content layout rect
        let contentRect = window.contentLayoutRect
        guard contentRect.width > 0 && contentRect.height > 0 else { return }
        
        // Calculate position at bottom right of content area in screen coordinates
        // Child windows use screen coordinates but move automatically with parent
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
        
        // Never show control until it has been used at least once (first recording)
        guard hasEverShownControl else {
            overlay.orderOut(nil)
            return
        }
        
        // Check if app is active and window is key/main
        let appIsActive = NSApplication.shared.isActive
        let windowIsKey = mainWindow.isKeyWindow
        let windowIsMain = mainWindow.isMainWindow
        let windowIsVisible = mainWindow.isVisible
        
        // Check if title bar is currently visible
        let titleBarIsVisible = mainWindow.titleVisibility == .visible
        
        // Always show controls while recording, during post-recording period, or when title bar is visible
        let shouldBeVisible = appIsActive && windowIsVisible && (windowIsKey || windowIsMain) && (isCurrentlyRecording || isInPostRecordingPeriod || titleBarIsVisible)
        
        if shouldBeVisible {
            // Ensure overlay is a child window for smooth movement
            if let childWindows = mainWindow.childWindows, !childWindows.contains(overlay) {
                mainWindow.addChildWindow(overlay, ordered: .above)
            } else if mainWindow.childWindows == nil {
                mainWindow.addChildWindow(overlay, ordered: .above)
            }
            
            // Batch window ordering operations to prevent flash
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            mainWindow.disableScreenUpdatesUntilFlush()
            
            // Position FIRST, then set level, then show - all in one batch
            updateRecordingControlPosition()
            overlay.order(.above, relativeTo: mainWindow.windowNumber)
            overlay.orderFront(nil)
            
            // Flush all window updates at once to prevent flash
            NSAnimationContext.endGrouping()
            mainWindow.flush()
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
            
            // In full screen mode, video gravity is set in handleWillEnterFullScreen
            // Just maintain the aspect ratio constraint
            if window.styleMask.contains(.fullScreen) {
                return
            }
            
            // In windowed mode, resize window to match aspect ratio
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
            
            // In windowed mode, use fill mode for better performance
            if let layer = captureLayer {
                layer.videoGravity = .resizeAspectFill
            }
        } else {
            window.contentResizeIncrements = NSMakeSize(1.0, 1.0)
            // When aspect ratio is not fixed, use fill mode
            if let layer = captureLayer {
                layer.videoGravity = .resizeAspectFill
            }
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
        
        // Apply aspect ratio fix BEFORE entering full screen to prevent zoom-then-correct effect
        // Set video layer gravity to letterbox mode if aspect ratio is fixed
        // This ensures video fills vertical space and letterboxes horizontally on wide screens
        if isAspectRatioFixed, let layer = captureLayer {
            layer.videoGravity = .resizeAspect
            NSLog("Set video gravity to resizeAspect for full screen (aspect ratio fixed)")
        }
        
        delegate?.windowManager(self, willEnterFullScreen: true)
        enableGameMode()
    }
    
    private func handleDidEnterFullScreen() {
        if !cursorHiddenForFullScreen {
            NSCursor.hide()
            cursorHiddenForFullScreen = true
        }
        // Video gravity was already set in handleWillEnterFullScreen
        // Just ensure aspect ratio constraints are maintained
        if let window = window, isAspectRatioFixed, #available(OSX 10.15, *), let input = videoInput {
            let height: Int32 = input.device.activeFormat.formatDescription.dimensions.height
            let width: Int32 = input.device.activeFormat.formatDescription.dimensions.width
            let size: NSSize =
                isLandscape()
                ? NSMakeSize(CGFloat(width), CGFloat(height))
                : NSMakeSize(CGFloat(height), CGFloat(width))
            window.contentAspectRatio = size
        }
        // Ensure window can receive keyboard events in full screen
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSLog("Made window key in full screen mode (windowNumber=%lu)", window.windowNumber)
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
        // Restore video gravity to fill mode for windowed mode
        if let layer = captureLayer {
            layer.videoGravity = .resizeAspectFill
            NSLog("Restored video gravity to resizeAspectFill for windowed mode")
        }
        // Restore aspect ratio constraint if it was enabled before entering full screen
        fixAspectRatio()
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
        CPSettingsManager.shared.setFrameProperties(
            x: Float(frame.minX),
            y: Float(frame.minY),
            width: Float(contentSize.width),
            height: Float(contentSize.height)
        )
    }
    
    func loadWindowFrame() {
        guard let window = window else { return }
        let savedW = CPSettingsManager.shared.frameWidth
        let savedH = CPSettingsManager.shared.frameHeight
        if 100 < savedW && 100 < savedH {
            let savedX = CPSettingsManager.shared.frameX
            let savedY = CPSettingsManager.shared.frameY
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
    weak var windowManager: CPWindowManager?
    
    init(windowManager: CPWindowManager) {
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

