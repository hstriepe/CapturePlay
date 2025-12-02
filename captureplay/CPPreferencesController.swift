// Copyright H. Striepe ©2025

import Cocoa

// MARK: - CPPreferencesControllerDelegate Protocol
protocol CPPreferencesControllerDelegate: AnyObject {
    func preferencesController(_ controller: CPPreferencesController, didSavePreferences: Void)
}

// MARK: - CPPreferencesController Class
class CPPreferencesController {
    
    // MARK: - Properties
    weak var delegate: CPPreferencesControllerDelegate?
    weak var parentWindow: NSWindow?
    
    private var preferencesDirectoryTextField: NSTextField?
    private var preferencesAlert: NSAlert?
    
    // MARK: - Initialization
    init(parentWindow: NSWindow?) {
        self.parentWindow = parentWindow
    }
    
    // MARK: - Preferences Dialog
    func showPreferences() {
        guard let parentWindow = parentWindow else {
            NSLog("Cannot show preferences: parent window is nil")
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "CapturePlay Settings"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        // Create a custom view for preferences (increased height for notification sounds toggle)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 230))
        
        // Performance Mode selector
        let performanceLabel = NSTextField(labelWithString: "Performance Mode:")
        performanceLabel.frame = NSRect(x: 20, y: 210, width: 150, height: 17)
        view.addSubview(performanceLabel)
        
        // Right-align popup with directory text field (which is 380 wide starting at x: 20, so right edge at x: 400)
        // Popup is 200 wide, so position at x: 200 to right-align at x: 400
        let performancePopup = NSPopUpButton(frame: NSRect(x: 200, y: 207, width: 200, height: 22))
        performancePopup.addItems(withTitles: ["Auto", "High", "Medium", "Low"])
        let currentMode = CPSettingsManager.shared.performanceMode.capitalized
        if let index = performancePopup.itemTitles.firstIndex(of: currentMode) {
            performancePopup.selectItem(at: index)
        } else {
            performancePopup.selectItem(at: 0) // Default to Auto
        }
        view.addSubview(performancePopup)
        
        // Toggle: Always show Video > Image submenu
        let imageMenuLabel = NSTextField(labelWithString: "Always show the Image submenu under Video")
        imageMenuLabel.frame = NSRect(x: 20, y: 180, width: 400, height: 17)
        view.addSubview(imageMenuLabel)
        
        let imageMenuToggle = NSSwitch(frame: NSRect(x: 429, y: 178, width: 51, height: 31))
        imageMenuToggle.state = CPSettingsManager.shared.alwaysShowImageMenu ? .on : .off
        imageMenuToggle.isEnabled = true
        view.addSubview(imageMenuToggle)
        
        // Toggle for auto display sleep in full screen
        let displaySleepLabel = NSTextField(labelWithString: "Automatically prevent display sleep during full screen")
        displaySleepLabel.frame = NSRect(x: 20, y: 150, width: 400, height: 17)
        view.addSubview(displaySleepLabel)
        
        let displaySleepToggle = NSSwitch(frame: NSRect(x: 429, y: 148, width: 51, height: 31))
        displaySleepToggle.state = CPSettingsManager.shared.autoDisplaySleepInFullScreen ? .on : .off
        displaySleepToggle.isEnabled = true
        view.addSubview(displaySleepToggle)
        
        // Toggle for enabling notification sounds
        let notificationSoundsLabel = NSTextField(labelWithString: "Play sound for capture notification")
        notificationSoundsLabel.frame = NSRect(x: 20, y: 120, width: 400, height: 17)
        view.addSubview(notificationSoundsLabel)
        
        let notificationSoundsToggle = NSSwitch(frame: NSRect(x: 429, y: 118, width: 51, height: 31))
        notificationSoundsToggle.state = CPSettingsManager.shared.enableNotificationSounds ? .on : .off
        notificationSoundsToggle.isEnabled = true
        view.addSubview(notificationSoundsToggle)
        
        // Toggle for showing video capture controls
        let captureControlsLabel = NSTextField(labelWithString: "Show video capture controls")
        captureControlsLabel.frame = NSRect(x: 20, y: 90, width: 400, height: 17)
        view.addSubview(captureControlsLabel)
        
        let captureControlsToggle = NSSwitch(frame: NSRect(x: 429, y: 88, width: 51, height: 31))
        captureControlsToggle.state = CPSettingsManager.shared.showVideoCaptureControls ? .on : .off
        captureControlsToggle.isEnabled = true
        view.addSubview(captureControlsToggle)
        
        // Label and text field for capture directory
        let directoryLabel = NSTextField(labelWithString: "Capture image directory:")
        directoryLabel.frame = NSRect(x: 20, y: 60, width: 150, height: 17)
        view.addSubview(directoryLabel)
        
        let directoryTextField = NSTextField(frame: NSRect(x: 20, y: 30, width: 380, height: 22))
        var directoryPath = CPSettingsManager.shared.captureImageDirectory
        if directoryPath.isEmpty {
            // Use actual user home directory, not sandboxed one
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            directoryPath = (homePath as NSString).appendingPathComponent("Documents/CapturePlay")
        }
        directoryTextField.stringValue = directoryPath
        view.addSubview(directoryTextField)
        preferencesDirectoryTextField = directoryTextField
        preferencesAlert = alert
        
        let browseButton = NSButton(title: "Browse…", target: self, action: #selector(browseCaptureDirectory(_:)))
        browseButton.frame = NSRect(x: 410, y: 28, width: 70, height: 26)
        view.addSubview(browseButton)
        
        alert.accessoryView = view
        
        // Store references for the closure
        weak var weakTextField = directoryTextField
        weak var weakDisplaySleepToggle = displaySleepToggle
        weak var weakImageMenuToggle = imageMenuToggle
        weak var weakCaptureControlsToggle = captureControlsToggle
        weak var weakNotificationSoundsToggle = notificationSoundsToggle
        weak var weakPerformancePopup = performancePopup
        weak var weakSelf = self
        
        // Use beginSheetModal instead of runModal to allow nested dialogs
        alert.beginSheetModal(for: parentWindow) { [weak self] response in
            self?.preferencesDirectoryTextField = nil
            self?.preferencesAlert = nil
            if response == .alertFirstButtonReturn {
                // OK clicked - save settings
                if let textField = weakTextField {
                    var path = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty {
                        // Always expand tilde paths when saving to avoid issues
                        path = weakSelf?.expandTildePath(path) ?? path
                        CPSettingsManager.shared.setCaptureImageDirectory(path)
                        NSLog("Saved capture directory: %@", path)
                    } else {
                        // Reset to default
                        CPSettingsManager.shared.setCaptureImageDirectory("")
                        NSLog("Reset capture directory to default")
                    }
                }
                if let toggle = weakDisplaySleepToggle {
                    CPSettingsManager.shared.setAutoDisplaySleepInFullScreen(toggle.state == .on)
                }
                if let toggle = weakImageMenuToggle {
                    CPSettingsManager.shared.setAlwaysShowImageMenu(toggle.state == .on)
                }
                if let toggle = weakCaptureControlsToggle {
                    CPSettingsManager.shared.setShowVideoCaptureControls(toggle.state == .on)
                }
                if let toggle = weakNotificationSoundsToggle {
                    CPSettingsManager.shared.setEnableNotificationSounds(toggle.state == .on)
                }
                if let popup = weakPerformancePopup {
                    let selectedTitle = popup.selectedItem?.title ?? "Auto"
                    let mode = selectedTitle.lowercased()
                    CPSettingsManager.shared.setPerformanceMode(mode)
                    NSLog("Performance mode set to: %@", mode)
                }
                CPSettingsManager.shared.saveSettings()
                if let strongSelf = weakSelf {
                    strongSelf.delegate?.preferencesController(strongSelf, didSavePreferences: ())
                }
            }
        }
    }
    
    // MARK: - Directory Browsing
    @objc private func browseCaptureDirectory(_ sender: NSButton) {
        guard let parentWindow = preferencesAlert?.window ?? self.parentWindow else {
            NSLog("Cannot browse directory: no parent window available")
            return
        }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory for captured images"
        
        let settings = CPSettingsManager.shared
        var initialPath = settings.captureImageDirectory
        if initialPath.isEmpty {
            // Use actual user home directory, not sandboxed one
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            initialPath = (homePath as NSString).appendingPathComponent("Documents/CapturePlay")
        }
        panel.directoryURL = URL(fileURLWithPath: initialPath)
        
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            if response == .OK, let url = panel.url {
                // Create security-scoped bookmark for persistent access
                do {
                    let bookmarkData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                    CPSettingsManager.shared.setCaptureImageDirectoryBookmark(bookmarkData)
                    CPSettingsManager.shared.setCaptureImageDirectory(url.path)
                    CPSettingsManager.shared.saveSettings()
                    NSLog("Saved security-scoped bookmark for directory: %@", url.path)
                } catch {
                    NSLog("WARNING: Failed to create security-scoped bookmark: %@", error.localizedDescription)
                    // Still save the path, but without bookmark
                    CPSettingsManager.shared.setCaptureImageDirectory(url.path)
                    CPSettingsManager.shared.setCaptureImageDirectoryBookmark(nil)
                    CPSettingsManager.shared.saveSettings()
                }
                
                if let textField = self?.preferencesDirectoryTextField {
                    textField.stringValue = url.path
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func expandTildePath(_ path: String) -> String {
        if path.hasPrefix("~") {
            // Use actual user home directory, not sandboxed one
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            if path == "~" {
                return homePath
            } else if path.hasPrefix("~/") {
                return (homePath as NSString).appendingPathComponent(String(path.dropFirst(2)))
            } else {
                // Handle ~username format (less common) - use NSString which expands to actual home
                return (path as NSString).expandingTildeInPath
            }
        }
        return path
    }
}

