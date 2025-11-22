// Copyright H. Striepe - 2025

import AVFoundation
import Cocoa
import UniformTypeIdentifiers

// MARK: - QCCaptureFileManagerDelegate Protocol
protocol QCCaptureFileManagerDelegate: AnyObject {
    func captureFileManager(_ manager: QCCaptureFileManager, didSaveImageTo url: URL, filename: String)
    func captureFileManager(_ manager: QCCaptureFileManager, didEncounterError error: Error, message: String)
    func captureFileManager(_ manager: QCCaptureFileManager, needsNotification title: String, body: String, sound: Bool)
}

// MARK: - QCCaptureFileManager Class
class QCCaptureFileManager {
    
    // MARK: - Properties
    weak var delegate: QCCaptureFileManagerDelegate?
    weak var window: NSWindow?
    weak var windowManager: QCWindowManager?
    weak var captureSession: AVCaptureSession?
    weak var captureLayer: AVCaptureVideoPreviewLayer?
    
    // MARK: - Initialization
    init() {
    }
    
    // MARK: - Capture Directory Management
    func getCaptureDirectory() -> URL? {
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
    
    // MARK: - Image Capture
    func captureImage() {
        guard let window = window else {
            let error = NSError(domain: "QCCaptureFileManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Window is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Window is not available")
            return
        }
        
        if window.styleMask.contains(.fullScreen) {
            let error = NSError(domain: "QCCaptureFileManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Capture is not supported as window is full screen"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Capture is not supported as window is full screen")
            return
        }
        
        guard let captureDir = getCaptureDirectory() else {
            let settings = QCSettingsManager.shared
            let dirPath = settings.captureImageDirectory.isEmpty ? "~/Pictures/CapturePlay" : settings.captureImageDirectory
            let message = "Unable to access or create the capture directory: \(dirPath)\n\nPlease check that:\n• The path is correct\n• You have write permissions\n• The directory can be created\n\nNote: For sandboxed apps, you may need to select the folder via the Browse button in Preferences to grant access."
            let error = NSError(domain: "QCCaptureFileManager", code: -3, userInfo: [NSLocalizedDescriptionKey: message])
            delegate?.captureFileManager(self, didEncounterError: error, message: message)
            return
        }
        
        guard captureSession != nil && captureLayer != nil else {
            let error = NSError(domain: "QCCaptureFileManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Capture session is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Capture session is not available")
            return
        }
        
        if #available(OSX 10.12, *) {
            captureImageToDirectory(captureDir)
        } else {
            let error = NSError(domain: "QCCaptureFileManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Unfortunately, saving images is only supported in Mac OSX 10.12 (Sierra) and higher."])
            delegate?.captureFileManager(self, didEncounterError: error, message: error.localizedDescription)
        }
    }
    
    func saveImage() {
        guard let window = window else {
            let error = NSError(domain: "QCCaptureFileManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Window is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Window is not available")
            return
        }
        
        if window.styleMask.contains(.fullScreen) {
            let error = NSError(domain: "QCCaptureFileManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Save is not supported as window is full screen"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Save is not supported as window is full screen")
            return
        }
        
        guard captureSession != nil else {
            let error = NSError(domain: "QCCaptureFileManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Capture session is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Capture session is not available")
            return
        }
        
        if #available(OSX 10.12, *) {
            saveImageWithSavePanel()
        } else {
            let error = NSError(domain: "QCCaptureFileManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Unfortunately, saving images is only supported in Mac OSX 10.12 (Sierra) and higher."])
            delegate?.captureFileManager(self, didEncounterError: error, message: error.localizedDescription)
        }
    }
    
    private func captureImageToDirectory(_ captureDir: URL) {
        guard let cgImage = captureWindowImage() else {
            let error = NSError(domain: "QCCaptureFileManager", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to capture window image"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Failed to capture window image")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
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
                NSLog("Could not write file - destination returned from CGImageDestinationCreateWithURL was nil")
                let error = NSError(domain: "QCCaptureFileManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Unfortunately, the image could not be saved to this location."])
                self.delegate?.captureFileManager(self, didEncounterError: error, message: error.localizedDescription)
            } else {
                CGImageDestinationAddImage(destination!, cgImage, nil)
                CGImageDestinationFinalize(destination!)
                NSLog("Image saved to: %@", fileURL.path)
                self.delegate?.captureFileManager(self, didSaveImageTo: fileURL, filename: filename)
                self.delegate?.captureFileManager(self, needsNotification: "Image Captured", body: "Saved: \(filename)", sound: true)
            }
        }
    }
    
    private func saveImageWithSavePanel() {
        guard let window = window else { return }
        guard let cgImage = captureWindowImage() else {
            let error = NSError(domain: "QCCaptureFileManager", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to capture window image"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Failed to capture window image")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let now: Date = Date()
            let dateFormatter: DateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let date: String = dateFormatter.string(from: now)
            dateFormatter.dateFormat = "h.mm.ss a"
            let time: String = dateFormatter.string(from: now)
            
            let panel: NSSavePanel = NSSavePanel()
            panel.nameFieldStringValue = String(
                format: "CapturePlay Image %@ at %@.png", date, time)
            panel.beginSheetModal(for: window) {
                (result: NSApplication.ModalResponse) in
                if result == NSApplication.ModalResponse.OK {
                    NSLog(panel.url!.absoluteString)
                    let destination: CGImageDestination? = CGImageDestinationCreateWithURL(
                        panel.url! as CFURL, UTType.png.identifier as CFString, 1, nil)
                    if destination == nil {
                        NSLog("Could not write file - destination returned from CGImageDestinationCreateWithURL was nil")
                        let error = NSError(domain: "QCCaptureFileManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Unfortunately, the image could not be saved to this location."])
                        self.delegate?.captureFileManager(self, didEncounterError: error, message: error.localizedDescription)
                    } else {
                        CGImageDestinationAddImage(destination!, cgImage, nil)
                        CGImageDestinationFinalize(destination!)
                    }
                }
            }
        }
    }
    
    // MARK: - Window Image Capture
    private func captureWindowImage() -> CGImage? {
        guard let window = window, let windowManager = windowManager else { return nil }
        
        // turn borderless on, capture image, return border to previous state
        let borderlessState: Bool = windowManager.isBorderless
        if borderlessState == false {
            NSLog("Removing border for capture")
            windowManager.removeBorder()
        }
        
        /* Pause the RunLoop for 0.1 sec to let the window repaint after removing the border */
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        
        let cgImage: CGImage? = CGWindowListCreateImage(
            CGRect.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
            .boundsIgnoreFraming)
        
        if borderlessState == false {
            windowManager.addBorder()
        }
        
        return cgImage
    }
    
    // MARK: - Clipboard Operations
    func copyImageToClipboard() -> Bool {
        guard let window = window else {
            let error = NSError(domain: "QCCaptureFileManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Window is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Window is not available")
            return false
        }
        
        if window.styleMask.contains(.fullScreen) {
            let error = NSError(domain: "QCCaptureFileManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Copy is not supported as window is full screen"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Copy is not supported as window is full screen")
            return false
        }
        
        guard captureSession != nil else {
            let error = NSError(domain: "QCCaptureFileManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Capture session is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Capture session is not available")
            return false
        }
        
        if #available(OSX 10.12, *) {
            guard let cgImage = captureWindowImage() else {
                let error = NSError(domain: "QCCaptureFileManager", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to capture window image"])
                delegate?.captureFileManager(self, didEncounterError: error, message: "Failed to capture window image")
                return false
            }
            
            // Convert CGImage to NSImage for clipboard
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            let image = NSImage(size: bitmapRep.size)
            image.addRepresentation(bitmapRep)
            
            // Copy to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            
            NSLog("Image copied to clipboard")
            return true
        } else {
            let error = NSError(domain: "QCCaptureFileManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Unfortunately, copying images is only supported in Mac OSX 10.12 (Sierra) and higher."])
            delegate?.captureFileManager(self, didEncounterError: error, message: error.localizedDescription)
            return false
        }
    }
    
    // MARK: - Folder Operations
    func openCaptureFolder() {
        guard let captureDir = getCaptureDirectory() else {
            let message = "Unable to access the capture directory.\n\nPlease check your settings."
            let error = NSError(domain: "QCCaptureFileManager", code: -7, userInfo: [NSLocalizedDescriptionKey: message])
            delegate?.captureFileManager(self, didEncounterError: error, message: message)
            return
        }
        
        // Open the folder in Finder
        NSWorkspace.shared.open(captureDir)
        NSLog("Opened capture folder in Finder: %@", captureDir.path)
    }
}

