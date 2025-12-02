// Copyright H. Striepe ©2025

import AVFoundation
import Cocoa
import UniformTypeIdentifiers

// MARK: - CPCaptureFileManagerDelegate Protocol
protocol CPCaptureFileManagerDelegate: AnyObject {
    func captureFileManager(_ manager: CPCaptureFileManager, didSaveImageTo url: URL, filename: String)
    func captureFileManager(_ manager: CPCaptureFileManager, didEncounterError error: Error, message: String)
    func captureFileManager(_ manager: CPCaptureFileManager, needsNotification title: String, body: String, sound: Bool)
}

// MARK: - CPCaptureFileManager Class
class CPCaptureFileManager {
    
    // MARK: - Properties
    weak var delegate: CPCaptureFileManagerDelegate?
    weak var window: NSWindow?
    weak var windowManager: CPWindowManager?
    weak var captureSession: AVCaptureSession?
    weak var captureLayer: AVCaptureVideoPreviewLayer?
    
    // Track security-scoped resource access for cleanup
    private var currentSecurityScopedURL: URL?
    
    // MARK: - Initialization
    init() {
    }
    
    // MARK: - Cleanup
    deinit {
        // Ensure we stop accessing any security-scoped resource on deallocation
        if let securityScopedURL = currentSecurityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
            currentSecurityScopedURL = nil
        }
    }
    
    /// Stop accessing the current security-scoped resource if one is active.
    /// This should be called after file operations complete, especially for video recording.
    func stopAccessingSecurityScopedResource() {
        if let securityScopedURL = currentSecurityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
            currentSecurityScopedURL = nil
        }
    }
    
    // MARK: - Capture Directory Management
    func getCaptureDirectory() -> URL? {
        let settings = CPSettingsManager.shared
        
        // First, try to resolve security-scoped bookmark if available
        if let bookmarkData = settings.captureImageDirectoryBookmark {
            var isStale = false
            do {
                let bookmarkURL = try URL(resolvingBookmarkData: bookmarkData, options: [.withoutUI, .withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if isStale {
                    NSLog("WARNING: Security-scoped bookmark is stale, will need to be refreshed")
                }
                
                // Stop accessing any previously accessed security-scoped resource
                if let previousURL = currentSecurityScopedURL {
                    previousURL.stopAccessingSecurityScopedResource()
                    currentSecurityScopedURL = nil
                }
                
                // Start accessing the security-scoped resource
                guard bookmarkURL.startAccessingSecurityScopedResource() else {
                    NSLog("ERROR: Failed to start accessing security-scoped resource: %@", bookmarkURL.path)
                    return nil
                }
                
                // Track this URL for cleanup
                currentSecurityScopedURL = bookmarkURL
                
                // Ensure directory exists and is writable
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: bookmarkURL.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        if FileManager.default.isWritableFile(atPath: bookmarkURL.path) {
                            NSLog("Using security-scoped capture directory: %@", bookmarkURL.path)
                            return bookmarkURL
                        } else {
                            bookmarkURL.stopAccessingSecurityScopedResource()
                            currentSecurityScopedURL = nil
                            NSLog("ERROR: Security-scoped directory is not writable: %@", bookmarkURL.path)
                            return nil
                        }
                    } else {
                        bookmarkURL.stopAccessingSecurityScopedResource()
                        currentSecurityScopedURL = nil
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
                                currentSecurityScopedURL = nil
                                NSLog("ERROR: Created directory but it is not writable: %@", bookmarkURL.path)
                                return nil
                            }
                        } else {
                            bookmarkURL.stopAccessingSecurityScopedResource()
                            currentSecurityScopedURL = nil
                            NSLog("ERROR: Directory creation reported success but directory does not exist: %@", bookmarkURL.path)
                            return nil
                        }
                    } catch {
                        bookmarkURL.stopAccessingSecurityScopedResource()
                        currentSecurityScopedURL = nil
                        NSLog("ERROR: Failed to create security-scoped directory: %@ - %@", bookmarkURL.path, error.localizedDescription)
                        return nil
                    }
                }
            } catch {
                NSLog("ERROR: Failed to resolve security-scoped bookmark: %@", error.localizedDescription)
                // Fall through to try path-based access
            }
        }
        
        // Fall back to path-based access
        var directoryPath: String = settings.captureImageDirectory
        
        // If no directory is set, use default ~/Documents/CapturePlay
        // Use actual user home directory, not sandboxed one
        if directoryPath.isEmpty {
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            directoryPath = (homePath as NSString).appendingPathComponent("Documents/CapturePlay")
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
    
    // MARK: - Image Capture
    func captureImage() {
        NSLog("captureImage() called - window: %@, fullScreen: %@", 
              window != nil ? "available" : "nil",
              window?.styleMask.contains(.fullScreen) == true ? "YES" : "NO")
        
        guard window != nil else {
            let error = NSError(domain: "CPCaptureFileManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Window is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Window is not available")
            return
        }
        
        guard let captureDir = getCaptureDirectory() else {
            let settings = CPSettingsManager.shared
            let dirPath = settings.captureImageDirectory.isEmpty ? "~/Documents/CapturePlay" : settings.captureImageDirectory
            let message = "Unable to access or create the capture directory: \(dirPath)\n\nPlease check that:\n• The path is correct\n• You have write permissions\n• The directory can be created\n\nNote: For sandboxed apps, you may need to select the folder via the Browse button in Preferences to grant access."
            let error = NSError(domain: "CPCaptureFileManager", code: -3, userInfo: [NSLocalizedDescriptionKey: message])
            delegate?.captureFileManager(self, didEncounterError: error, message: message)
            return
        }
        
        guard captureSession != nil && captureLayer != nil else {
            let error = NSError(domain: "CPCaptureFileManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Capture session is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Capture session is not available")
            return
        }
        
        if #available(OSX 10.12, *) {
            captureImageToDirectory(captureDir)
        } else {
            let error = NSError(domain: "CPCaptureFileManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Unfortunately, saving images is only supported in Mac OSX 10.12 (Sierra) and higher."])
            delegate?.captureFileManager(self, didEncounterError: error, message: error.localizedDescription)
        }
    }
    
    func saveImage() {
        guard window != nil else {
            let error = NSError(domain: "CPCaptureFileManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Window is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Window is not available")
            return
        }
        
        guard captureSession != nil else {
            let error = NSError(domain: "CPCaptureFileManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Capture session is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Capture session is not available")
            return
        }
        
        if #available(OSX 10.12, *) {
            saveImageWithSavePanel()
        } else {
            let error = NSError(domain: "CPCaptureFileManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Unfortunately, saving images is only supported in Mac OSX 10.12 (Sierra) and higher."])
            delegate?.captureFileManager(self, didEncounterError: error, message: error.localizedDescription)
        }
    }
    
    private func captureImageToDirectory(_ captureDir: URL) {
        captureWindowImage { [weak self] cgImage in
            guard let self = self else { return }
            guard let cgImage = cgImage else {
                let error = NSError(domain: "CPCaptureFileManager", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to capture window image"])
                DispatchQueue.main.async {
                    self.delegate?.captureFileManager(self, didEncounterError: error, message: "Failed to capture window image")
                }
                return
            }
            
            // Move image encoding to background queue to avoid blocking UI
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let now: Date = Date()
                let dateFormatter: DateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let date: String = dateFormatter.string(from: now)
                dateFormatter.dateFormat = "HH.mm.ss"
                let time: String = dateFormatter.string(from: now)
                
                let filename = String(format: "CapturePlay Image %@ at %@.png", date, time)
                let fileURL = captureDir.appendingPathComponent(filename)
                
                guard let destination = CGImageDestinationCreateWithURL(
                    fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    NSLog("Could not write file - destination returned from CGImageDestinationCreateWithURL was nil")
                    let error = NSError(domain: "CPCaptureFileManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Unfortunately, the image could not be saved to this location."])
                    DispatchQueue.main.async {
                        self.delegate?.captureFileManager(self, didEncounterError: error, message: error.localizedDescription)
                    }
                    return
                }
                
                CGImageDestinationAddImage(destination, cgImage, nil)
                CGImageDestinationFinalize(destination)
                NSLog("Image saved to: %@", fileURL.path)
                
                // Stop accessing security-scoped resource after file operation completes
                if let securityScopedURL = self.currentSecurityScopedURL, securityScopedURL == captureDir {
                    securityScopedURL.stopAccessingSecurityScopedResource()
                    self.currentSecurityScopedURL = nil
                }
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.delegate?.captureFileManager(self, didSaveImageTo: fileURL, filename: filename)
                    self.delegate?.captureFileManager(self, needsNotification: "Image Captured", body: "Saved: \(filename)", sound: true)
                }
            }
        }
    }
    
    private func saveImageWithSavePanel() {
        guard window != nil else { return }
        
        captureWindowImage { [weak self] cgImage in
            guard let self = self else { return }
            guard let cgImage = cgImage else {
                let error = NSError(domain: "CPCaptureFileManager", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to capture window image"])
                DispatchQueue.main.async {
                    self.delegate?.captureFileManager(self, didEncounterError: error, message: "Failed to capture window image")
                }
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let window = self.window else { return }
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
                        guard let saveURL = panel.url else { return }
                        NSLog(saveURL.absoluteString)
                        
                        // Move file writing to background queue
                        DispatchQueue.global(qos: .userInitiated).async {
                            guard let destination = CGImageDestinationCreateWithURL(
                                saveURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                                NSLog("Could not write file - destination returned from CGImageDestinationCreateWithURL was nil")
                                let error = NSError(domain: "CPCaptureFileManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Unfortunately, the image could not be saved to this location."])
                                DispatchQueue.main.async {
                                    self.delegate?.captureFileManager(self, didEncounterError: error, message: error.localizedDescription)
                                }
                                return
                            }
                            
                            CGImageDestinationAddImage(destination, cgImage, nil)
                            CGImageDestinationFinalize(destination)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Window Image Capture
    private func captureWindowImage(completion: @escaping (CGImage?) -> Void) {
        guard let window = window, let windowManager = windowManager else {
            NSLog("captureWindowImage: window or windowManager is nil")
            completion(nil)
            return
        }
        
        let isFullScreen = window.styleMask.contains(.fullScreen)
        NSLog("captureWindowImage: windowNumber=%lu, fullScreen=%@", window.windowNumber, isFullScreen ? "YES" : "NO")
        
        // In full screen, don't modify border state
        let borderlessState: Bool = windowManager.isBorderless
        if !isFullScreen && borderlessState == false {
            NSLog("Removing border for capture")
            windowManager.removeBorder()
        }
        
        // Use async dispatch instead of blocking RunLoop
        // Give the window a moment to repaint after removing the border (if needed)
        let delay = isFullScreen ? 0.0 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSLog("Capturing window image (windowNumber=%lu)", window.windowNumber)
            let cgImage: CGImage? = CGWindowListCreateImage(
                CGRect.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                .boundsIgnoreFraming)
            
            if !isFullScreen && borderlessState == false {
                windowManager.addBorder()
            }
            
            if cgImage == nil {
                NSLog("ERROR: CGWindowListCreateImage returned nil")
            } else {
                NSLog("Successfully captured window image: %dx%d pixels", cgImage!.width, cgImage!.height)
            }
            
            // Crop to video content if aspect ratio is fixed and video is letterboxed
            let croppedImage = self.cropToVideoContentIfNeeded(cgImage, window: window)
            completion(croppedImage)
        }
    }
    
    // MARK: - Image Cropping
    /// Crops the captured image to remove black letterboxing when aspect ratio is fixed.
    /// Returns the original image if cropping is not needed or not possible.
    private func cropToVideoContentIfNeeded(_ image: CGImage?, window: NSWindow) -> CGImage? {
        guard let image = image,
              let windowManager = windowManager,
              let videoInput = windowManager.videoInput,
              windowManager.isAspectRatioFixed else {
            // No cropping needed if aspect ratio is not fixed
            return image
        }
        
        // Check if video layer is using letterbox mode (resizeAspect)
        // If using fill mode (resizeAspectFill), no cropping needed
        guard let captureLayer = captureLayer,
              captureLayer.videoGravity == .resizeAspect else {
            return image
        }
        
        // Get video source dimensions
        let videoDimensions = videoInput.device.activeFormat.formatDescription.dimensions
        let videoWidth = CGFloat(videoDimensions.width)
        let videoHeight = CGFloat(videoDimensions.height)
        
        // Account for rotation
        let isLandscape = windowManager.isLandscape()
        let sourceAspectRatio: CGFloat
        if isLandscape {
            sourceAspectRatio = videoWidth / videoHeight
        } else {
            sourceAspectRatio = videoHeight / videoWidth
        }
        
        // Get window content dimensions (in points)
        let windowContentSize = window.contentLayoutRect.size
        let windowAspectRatio = windowContentSize.width / windowContentSize.height
        
        // Calculate the actual video content rectangle within the window
        let videoContentRect: CGRect
        if sourceAspectRatio > windowAspectRatio {
            // Video is wider than window - letterboxing on top/bottom
            // Video fills width, calculate height
            let videoContentHeight = windowContentSize.width / sourceAspectRatio
            let letterboxHeight = (windowContentSize.height - videoContentHeight) / 2.0
            videoContentRect = CGRect(
                x: 0,
                y: letterboxHeight,
                width: windowContentSize.width,
                height: videoContentHeight
            )
        } else {
            // Video is taller than window - letterboxing on sides
            // Video fills height, calculate width
            let videoContentWidth = windowContentSize.height * sourceAspectRatio
            let letterboxWidth = (windowContentSize.width - videoContentWidth) / 2.0
            videoContentRect = CGRect(
                x: letterboxWidth,
                y: 0,
                width: videoContentWidth,
                height: windowContentSize.height
            )
        }
        
        // Convert points to pixels (account for Retina display)
        let scale = window.backingScaleFactor
        let pixelRect = CGRect(
            x: videoContentRect.origin.x * scale,
            y: videoContentRect.origin.y * scale,
            width: videoContentRect.size.width * scale,
            height: videoContentRect.size.height * scale
        )
        
        // Ensure pixel rect is within image bounds
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let clampedRect = CGRect(
            x: max(0, min(pixelRect.origin.x, imageWidth)),
            y: max(0, min(pixelRect.origin.y, imageHeight)),
            width: min(pixelRect.width, imageWidth - max(0, pixelRect.origin.x)),
            height: min(pixelRect.height, imageHeight - max(0, pixelRect.origin.y))
        )
        
        // Only crop if there's significant letterboxing (more than 1 pixel)
        guard clampedRect.width > 1 && clampedRect.height > 1,
              clampedRect.width < imageWidth - 1 || clampedRect.height < imageHeight - 1 else {
            // No significant letterboxing, return original
            return image
        }
        
        // Crop the image to video content
        guard let croppedImage = image.cropping(to: clampedRect) else {
            NSLog("Failed to crop image to video content")
            return image
        }
        
        NSLog("Cropped image from %dx%d to %dx%d (removed letterboxing)", 
              image.width, image.height, croppedImage.width, croppedImage.height)
        return croppedImage
    }
    
    // MARK: - Clipboard Operations
    /// Copies the current window image to the clipboard.
    /// 
    /// - Returns: `true` if the copy operation was initiated successfully (operation is asynchronous).
    ///            `false` if the operation cannot be started (window unavailable, full screen, etc.).
    ///            Note: The actual copy happens asynchronously. Errors are reported via the delegate.
    func copyImageToClipboard() -> Bool {
        guard window != nil else {
            let error = NSError(domain: "CPCaptureFileManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Window is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Window is not available")
            return false
        }
        
        guard captureSession != nil else {
            let error = NSError(domain: "CPCaptureFileManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Capture session is not available"])
            delegate?.captureFileManager(self, didEncounterError: error, message: "Capture session is not available")
            return false
        }
        
        if #available(OSX 10.12, *) {
            captureWindowImage { [weak self] cgImage in
                guard let self = self else { return }
                guard let cgImage = cgImage else {
                    let error = NSError(domain: "CPCaptureFileManager", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to capture window image"])
                    DispatchQueue.main.async {
                        self.delegate?.captureFileManager(self, didEncounterError: error, message: "Failed to capture window image")
                    }
                    return
                }
                
                // Convert CGImage to NSImage for clipboard (on main thread for UI operations)
                DispatchQueue.main.async {
                    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                    let image = NSImage(size: bitmapRep.size)
                    image.addRepresentation(bitmapRep)
                    
                    // Copy to clipboard
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
                    
                    NSLog("Image copied to clipboard")
                }
            }
            // Return true to indicate operation was initiated successfully
            // Actual completion/errors are handled asynchronously via delegate
            return true
        } else {
            let error = NSError(domain: "CPCaptureFileManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Unfortunately, copying images is only supported in Mac OSX 10.12 (Sierra) and higher."])
            delegate?.captureFileManager(self, didEncounterError: error, message: error.localizedDescription)
            return false
        }
    }
    
    // MARK: - Folder Operations
    func openCaptureFolder() {
        guard let captureDir = getCaptureDirectory() else {
            let message = "Unable to access the capture directory.\n\nPlease check your settings."
            let error = NSError(domain: "CPCaptureFileManager", code: -7, userInfo: [NSLocalizedDescriptionKey: message])
            delegate?.captureFileManager(self, didEncounterError: error, message: message)
            return
        }
        
        // Open the folder in Finder
        NSWorkspace.shared.open(captureDir)
        NSLog("Opened capture folder in Finder: %@", captureDir.path)
        
        // Stop accessing security-scoped resource after opening (NSWorkspace.open handles its own access)
        // Note: We keep access briefly to ensure the open operation succeeds, then release
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let self = self, let securityScopedURL = self.currentSecurityScopedURL, securityScopedURL == captureDir {
                securityScopedURL.stopAccessingSecurityScopedResource()
                self.currentSecurityScopedURL = nil
            }
        }
    }
}

