// Copyright H. Striepe - 2025

import Cocoa

// MARK: - QCPreferencesControllerDelegate Protocol
protocol QCPreferencesControllerDelegate: AnyObject {
    func preferencesController(_ controller: QCPreferencesController, didSavePreferences: Void)
}

// MARK: - QCPreferencesController Class
class QCPreferencesController {
    
    // MARK: - Properties
    weak var delegate: QCPreferencesControllerDelegate?
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
                weakSelf?.delegate?.preferencesController(weakSelf!, didSavePreferences: ())
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
        
        let settings = QCSettingsManager.shared
        var initialPath = settings.captureImageDirectory
        if initialPath.isEmpty {
            let homePath = NSHomeDirectory()
            initialPath = (homePath as NSString).appendingPathComponent("Pictures/CapturePlay")
        }
        panel.directoryURL = URL(fileURLWithPath: initialPath)
        
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
    
    // MARK: - Helper Methods
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
}

