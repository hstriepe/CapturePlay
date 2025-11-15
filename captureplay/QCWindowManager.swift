// Copyright H. Striepe - 2025

import AVFoundation
import Cocoa

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
    
    // MARK: - Window Border Management
    func addBorder() {
        guard let window = window else { return }
        window.styleMask = defaultBorderStyle
        window.title = windowTitle
        window.level = convertToNSWindowLevel(Int(CGWindowLevelForKey(.normalWindow)))
        window.isMovableByWindowBackground = false
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
    
    func swapWH() {
        guard let window = window else { return }
        var currentSize: CGSize = window.contentLayoutRect.size
        swap(&currentSize.height, &currentSize.width)
        window.setContentSize(currentSize)
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
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

