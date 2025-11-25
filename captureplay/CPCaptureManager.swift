// Copyright H. Striepe ©2025
// Portions copyright Simon Guest ©2025

import AVFoundation
import Cocoa
import CoreVideo

// MARK: - CPCaptureManagerDelegate Protocol
protocol CPCaptureManagerDelegate: AnyObject {
    func captureManager(_ manager: CPCaptureManager, didDetectDevices devices: [AVCaptureDevice])
    func captureManager(_ manager: CPCaptureManager, didChangeDevice device: AVCaptureDevice, deviceIndex: Int)
    func captureManager(_ manager: CPCaptureManager, didStartRecordingTo url: URL)
    func captureManager(_ manager: CPCaptureManager, didFinishRecordingTo url: URL, error: Error?)
    func captureManager(_ manager: CPCaptureManager, didEncounterError error: Error, message: String)
    func captureManager(_ manager: CPCaptureManager, needsAudioDeviceUpdateFor videoDevice: AVCaptureDevice)
    func captureManager(_ manager: CPCaptureManager, needsSettingsApplication: Void)
    func captureManager(_ manager: CPCaptureManager, needsWindowTitleUpdate title: String)
    func captureManager(_ manager: CPCaptureManager, needsDeviceNameUpdate name: String)
    func captureManager(_ manager: CPCaptureManager, didChangeRecordingState isRecording: Bool)
}

// MARK: - CPCaptureManager Class
class CPCaptureManager: NSObject {
    
    // MARK: - Properties
    weak var delegate: CPCaptureManagerDelegate?
    
    private(set) var devices: [AVCaptureDevice] = []
    private(set) var captureSession: AVCaptureSession?
    private(set) var captureLayer: AVCaptureVideoPreviewLayer?
    private(set) var input: AVCaptureDeviceInput?
    private(set) var movieFileOutput: AVCaptureMovieFileOutput?
    private(set) var currentVideoDevice: AVCaptureDevice?
    private(set) var selectedDeviceIndex: Int = 0
    private(set) var isRecording: Bool = false {
        didSet {
            delegate?.captureManager(self, didChangeRecordingState: isRecording)
        }
    }
    
    // Track last stop time for cooldown
    private var lastStopTime: Date?
    
    
    // Dependencies (will be injected)
    weak var audioManager: CPAudioManager?
    private var recordingAudioInput: AVCaptureDeviceInput?
    var previewView: NSView? // Preview view for capture layer
    
    let defaultDeviceIndex: Int = 0
    
    // MARK: - Default Device Selection
    func getPreferredDefaultDeviceIndex(from devices: [AVCaptureDevice]) -> Int {
        // Never select Continuity Camera as default - prefer physical capture devices
        for (index, device) in devices.enumerated() {
            if #available(macOS 13.0, *) {
                if device.deviceType == .continuityCamera {
                    NSLog("Skipping Continuity Camera '%@' for default selection", device.localizedName)
                    continue
                }
            }
            NSLog("Selected '%@' as default video device", device.localizedName)
            return index
        }
        
        // Fallback to first device if no non-Continuity devices found
        NSLog("No non-Continuity devices found, using first available device")
        return defaultDeviceIndex
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
    }
    
    // MARK: - Device Detection
    func detectVideoDevices() {
        NSLog("Detecting video devices...")
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .externalUnknown]
        
        if #available(macOS 13.0, *) {
            deviceTypes.append(.continuityCamera)
        }
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified)
        let discoveredDevices = discoverySession.devices.sorted {
            $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending
        }
        
        if discoveredDevices.isEmpty {
            // Notify that no video content is available
            let message = "Unfortunately, you don't appear to have any cameras connected. Goodbye for now!"
            let error = NSError(domain: "CPCaptureManager", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            delegate?.captureManager(self, didEncounterError: error, message: message)
            NSApp.terminate(nil)
        } else {
            NSLog("%d devices found", discoveredDevices.count)
            // Log all detected devices
            for (index, device) in discoveredDevices.enumerated() {
                NSLog("Device %d: %@ (type: %@)", index, device.localizedName, device.deviceType.rawValue)
            }
            
            let previousIDs = devices.map { $0.uniqueID }
            let newIDs = discoveredDevices.map { $0.uniqueID }
            let devicesChanged = previousIDs != newIDs
            
            // Update stored devices regardless so our list remains sorted/deterministic
            self.devices = discoveredDevices
            
            if devicesChanged || captureSession == nil {
                NSLog("Calling delegate with %d devices", devices.count)
                delegate?.captureManager(self, didDetectDevices: devices)
            } else {
                NSLog("No changes in video device list detected; skipping delegate update")
            }
        }
    }
    
    // MARK: - Capture Session Management
    func startCaptureWithVideoDevice(deviceIndex: Int) {
        guard deviceIndex >= 0 && deviceIndex < devices.count else {
            NSLog("Invalid device index: %d", deviceIndex)
            return
        }
        
        NSLog("Starting capture with device index %d", deviceIndex)
        let device = devices[deviceIndex]
        
        // Check if we're switching to the same device
        if let session = captureSession, let currentInput = input {
            let currentDevice = currentInput.device
            guard currentDevice != device else {
                NSLog("Device is already active, skipping restart")
                return
            }
            session.stopRunning()
            // Temporarily notify no content while switching devices
        }
        
        // Create new session
        let session = AVCaptureSession()
        movieFileOutput = nil
        
        do {
            // Configure session preset for performance
            configureSessionPreset(session: session, device: device)
            
            let deviceInput = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            
            if session.canAddInput(deviceInput) {
                session.addInput(deviceInput)
                self.input = deviceInput
            }
            
            // Optimize video format for performance on slower systems
            optimizeVideoFormat(device: device)
            
            // Add movie file output for video recording
            let movieOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
                self.movieFileOutput = movieOutput
                NSLog("Movie file output added successfully for device: %@", device.localizedName)
            } else {
                NSLog("WARNING: Cannot add movie file output for device: %@ - recording may not work", device.localizedName)
            }
            
            
            session.commitConfiguration()
            
            // Setup preview layer with performance optimizations
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
            previewLayer.connection?.isVideoMirrored = false
            // Use resizeAspectFill for better performance (less scaling work)
            previewLayer.videoGravity = .resizeAspectFill
            
            // Frame rate smoothing optimizations for slower systems
            configurePreviewLayerSmoothing(previewLayer: previewLayer, device: device)
            
            if let previewView = previewView {
                previewView.layer = previewLayer
                // Don't set background color here - let window manager control it
                previewView.wantsLayer = true
                
                // Enable hardware acceleration and optimize rendering
                if let layer = previewView.layer {
                    // Use Metal for hardware-accelerated rendering
                    layer.contentsGravity = .resizeAspectFill
                    // Enable edge antialiasing for smoother edges (minimal performance cost)
                    layer.edgeAntialiasingMask = []
                    // Optimize for video content
                    layer.isOpaque = true
                    // Use optimal rendering mode for video
                    if #available(macOS 10.15, *) {
                        layer.contentsFormat = .RGBA8Uint
                    }
                }
            }
            
            self.captureSession = session
            self.captureLayer = previewLayer
            self.currentVideoDevice = device
            self.selectedDeviceIndex = deviceIndex
            
            // Log device capabilities for debugging
            NSLog("Device capabilities for %@:", device.localizedName)
            NSLog("  - Device type: %@", device.deviceType.rawValue)
            NSLog("  - Has video: %@", device.hasMediaType(.video) ? "YES" : "NO")
            NSLog("  - Active format: %@", device.activeFormat.description)
            NSLog("  - Movie output available: %@", movieFileOutput != nil ? "YES" : "NO")
            
            // Notify delegate
            let windowTitle = String(format: "CapturePlay: [%@]", device.localizedName)
            delegate?.captureManager(self, needsWindowTitleUpdate: windowTitle)
            delegate?.captureManager(self, needsDeviceNameUpdate: device.localizedName)
            delegate?.captureManager(self, didChangeDevice: device, deviceIndex: deviceIndex)
            delegate?.captureManager(self, needsAudioDeviceUpdateFor: device)
            
            if !session.isRunning {
                session.startRunning()
            }
            
            // Don't notify content state here - let the frame analysis detect actual content
            delegate?.captureManager(self, needsSettingsApplication: ())
            
        } catch {
            NSLog("Error while opening device: %@", error.localizedDescription)
            // Notify that video content is not available due to error
            let message = "Unfortunately, there was an error when trying to access the camera. Try again or select a different one."
            delegate?.captureManager(self, didEncounterError: error, message: message)
        }
    }
    
    // MARK: - Recording Management
    func startRecording(to captureDirectory: URL) {
        NSLog("startRecording called - isRecording: %@", isRecording ? "YES" : "NO")
        
        // Check if device supports recording
        if !supportsRecording() {
            NSLog("ERROR: Device does not support recording")
            if let device = currentVideoDevice {
                NSLog("Current device: %@ (type: %@)", device.localizedName, device.deviceType.rawValue)
                let message = "Video recording is not supported by '\(device.localizedName)'. This capture device may not be compatible with video recording. Image capture will still work normally."
                let error = NSError(domain: "CPCaptureManager", code: -2, userInfo: [NSLocalizedDescriptionKey: message])
                delegate?.captureManager(self, didEncounterError: error, message: message)
            } else {
                let error = NSError(domain: "CPCaptureManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Video recording is not available. Please ensure a video device is selected."])
                delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
            }
            return
        }
        
        guard let session = captureSession else {
            NSLog("ERROR: captureSession is nil")
            let error = NSError(domain: "CPCaptureManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Capture session is not available."])
            delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
            return
        }
        
        // Check for 1-second cooldown after stopping
        if let lastStop = lastStopTime {
            let timeSinceStop = Date().timeIntervalSince(lastStop)
            if timeSinceStop < 1.0 {
                let remainingTime = 1.0 - timeSinceStop
                NSLog("Recording cooldown active. Waiting %.2f seconds...", remainingTime)
                DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                    self?.startRecording(to: captureDirectory)
                }
                return
            }
        }
        
        // Ensure session is running
        NSLog("Session running state: %@", session.isRunning ? "YES" : "NO")
        if !session.isRunning {
            NSLog("Starting capture session...")
            session.startRunning()
            // Give it a moment to establish connections
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                NSLog("Session start delay completed, attempting to start recording...")
                self?.startVideoRecording(to: captureDirectory)
            }
        } else {
            NSLog("Session already running, starting recording immediately...")
            startVideoRecording(to: captureDirectory)
        }
    }
    
    func stopRecording() {
        guard let movieOutput = movieFileOutput else { return }
        movieOutput.stopRecording()
        NSLog("Stopping video recording...")
    }
    
    func toggleRecording(captureDirectory: URL?) {
        if isRecording {
            stopRecording()
        } else {
            guard let captureDir = captureDirectory else {
                let error = NSError(domain: "CPCaptureManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unable to access the capture directory."])
                delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
                return
            }
            startRecording(to: captureDir)
        }
    }
    
    private func startVideoRecording(to captureDir: URL) {
        guard let movieOutput = movieFileOutput else {
            NSLog("ERROR: movieFileOutput is nil - cannot start recording")
            let error = NSError(domain: "CPCaptureManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Video recording is not available. Please ensure a video device is selected."])
            delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
            return
        }
        
        guard let session = captureSession, session.isRunning else {
            NSLog("ERROR: Capture session is not running - cannot start recording")
            let error = NSError(domain: "CPCaptureManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Capture session is not running."])
            delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
            return
        }
        
        guard ensureRecordingAudioInput() else {
            let error = NSError(
                domain: "CPCaptureManager",
                code: -8,
                userInfo: [NSLocalizedDescriptionKey: "Unable to add the selected audio source to the recording session."]
            )
            delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
            return
        }
        
        NSLog("Starting video recording - session running: %@", 
              session.isRunning ? "YES" : "NO")
        
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
                let error = NSError(domain: "CPCaptureManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Cannot overwrite existing file: \(fileURL.lastPathComponent)"])
                delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
                return
            }
        }
        
        // Check if directory is writable
        let directoryPath = fileURL.deletingLastPathComponent().path
        if !fileManager.isWritableFile(atPath: directoryPath) {
            NSLog("ERROR: Directory is not writable: %@", directoryPath)
            let error = NSError(domain: "CPCaptureManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Directory is not writable: \(directoryPath)"])
            delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
            return
        }
        
        // Start recording
        NSLog("Attempting to start recording to: %@", fileURL.path)
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        isRecording = true
        NSLog("Recording started successfully to: %@", fileURL.path)
        delegate?.captureManager(self, didStartRecordingTo: fileURL)
    }
    
    private func ensureRecordingAudioInput() -> Bool {
        guard let session = captureSession else { return false }
        if let existingAudioInput = recordingAudioInput,
           session.inputs.contains(existingAudioInput) {
            return true
        }
        guard let provider = audioManager,
              let newAudioInput = provider.makeRecordingInput() else {
            NSLog("Unable to build recording audio input from provider")
            return false
        }
        
        session.beginConfiguration()
        var added = false
        if session.canAddInput(newAudioInput) {
            session.addInput(newAudioInput)
            recordingAudioInput = newAudioInput
            added = true
        }
        session.commitConfiguration()
        
        if !added {
            recordingAudioInput = nil
            NSLog("Recording audio input could not be added to session")
        }
        return added
    }
    
    private func detachRecordingAudioInput() {
        guard let session = captureSession,
              let audioInput = recordingAudioInput else { return }
        session.beginConfiguration()
        session.removeInput(audioInput)
        session.commitConfiguration()
        recordingAudioInput = nil
    }
    
    private func configureRecordingSettings(movieOutput: AVCaptureMovieFileOutput) {
        // Configure audio settings for QuickTime compatibility (AAC, 256Kbps)
        if let audioConnection = movieOutput.connection(with: .audio) {
            // Get audio format from input if available
            var inputSampleRate: Double = 44100.0
            var channels: Int = 2
            
            if let audioInput = recordingAudioInput {
                let formatDesc = audioInput.device.activeFormat.formatDescription
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                if let asbd = asbd?.pointee {
                    inputSampleRate = Double(asbd.mSampleRate)
                    channels = Int(asbd.mChannelsPerFrame)
                    NSLog("Input audio format: %.0f Hz, %d channels", inputSampleRate, channels)
                }
            }
            
            // Convert to AAC-compatible sample rate
            let outputSampleRate = getAACCompatibleSampleRate(inputRate: inputSampleRate)
            NSLog("Converting sample rate from %.0f Hz to %.0f Hz for AAC compatibility", inputSampleRate, outputSampleRate)
            
            // Set AAC audio settings for QuickTime compatibility
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: outputSampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 256000
            ]
            
            movieOutput.setOutputSettings(audioSettings, for: audioConnection)
            NSLog("Configured AAC audio: %.0f Hz, %d channels, 256Kbps", outputSampleRate, channels)
        } else {
            NSLog("Note: No audio connection available - video will be recorded without audio")
        }
        
        // Video will use source resolution automatically
        // No need to set custom video settings - system will use appropriate defaults
        if movieOutput.connection(with: .video) != nil, let deviceInput = input {
            let videoDevice = deviceInput.device
            let dimensions = videoDevice.activeFormat.formatDescription.dimensions
            NSLog("Video recording at source resolution: %dx%d", dimensions.width, dimensions.height)
        } else {
            NSLog("ERROR: No video connection available")
        }
    }
    
    // MARK: - Preview Layer Access
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return captureLayer
    }
    
    func getCurrentDevice() -> AVCaptureDevice? {
        return currentVideoDevice
    }
    
    func getInput() -> AVCaptureDeviceInput? {
        return input
    }
    
    func stopCapture() {
        captureSession?.stopRunning()
        captureSession = nil
        captureLayer = nil
        input = nil
        currentVideoDevice = nil
    }
    
    // MARK: - Device Capability Checking
    func supportsRecording() -> Bool {
        guard let device = currentVideoDevice,
              let session = captureSession else {
            return false
        }
        
        // Check if we can add a movie file output to the session
        let testOutput = AVCaptureMovieFileOutput()
        let canAdd = session.canAddOutput(testOutput)
        
        NSLog("Recording support check for %@: %@", device.localizedName, canAdd ? "YES" : "NO")
        return canAdd && movieFileOutput != nil
    }
    
    // MARK: - Performance Optimization
    private func configureSessionPreset(session: AVCaptureSession, device: AVCaptureDevice) {
        let performanceMode = CPSettingsManager.shared.performanceMode
        
        // Auto-detect performance mode if set to "auto"
        var effectiveMode = performanceMode
        if performanceMode == "auto" {
            // Detect system performance - use CPU count and available memory as indicators
            let processorCount = ProcessInfo.processInfo.processorCount
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            
            // Conservative thresholds for slower systems
            if processorCount <= 4 || physicalMemory < 8_000_000_000 { // Less than 8GB RAM or 4 cores
                effectiveMode = "medium"
                NSLog("Auto-detected slower system: %d cores, %.1f GB RAM - using medium performance mode", processorCount, Double(physicalMemory) / 1_000_000_000.0)
            } else {
                effectiveMode = "high"
            }
        }
        
        // Configure session preset based on performance mode
        switch effectiveMode {
        case "low":
            if session.canSetSessionPreset(.medium) {
                session.sessionPreset = .medium
                NSLog("Using medium session preset for low performance mode")
            } else {
                session.sessionPreset = .high
                NSLog("Medium preset not available, using high")
            }
        case "medium":
            if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
                NSLog("Using high session preset for medium performance mode")
            } else {
                session.sessionPreset = .photo
                NSLog("High preset not available, using photo")
            }
        case "high", "auto":
            // Use highest quality available
            if session.canSetSessionPreset(.photo) {
                session.sessionPreset = .photo
                NSLog("Using photo session preset for high performance mode")
            } else if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
                NSLog("Using high session preset")
            } else {
                session.sessionPreset = .medium
                NSLog("Using medium session preset (fallback)")
            }
        default:
            session.sessionPreset = .high
            NSLog("Unknown performance mode '%@', using high preset", performanceMode)
        }
    }
    
    private func optimizeVideoFormat(device: AVCaptureDevice) {
        let performanceMode = CPSettingsManager.shared.performanceMode
        
        // Skip format optimization if in high performance mode
        guard performanceMode == "auto" || performanceMode == "medium" || performanceMode == "low" else {
            return
        }
        
        // Auto-detect if needed
        var effectiveMode = performanceMode
        if performanceMode == "auto" {
            let processorCount = ProcessInfo.processInfo.processorCount
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            if processorCount <= 4 || physicalMemory < 8_000_000_000 {
                effectiveMode = "medium"
            } else {
                return // High performance system, use native format
            }
        }
        
        // Find a lower resolution format for slower systems
        if effectiveMode == "low" || effectiveMode == "medium" {
            let availableFormats = device.formats.sorted { format1, format2 in
                let dims1 = format1.formatDescription.dimensions
                let dims2 = format2.formatDescription.dimensions
                let area1 = Int(dims1.width) * Int(dims1.height)
                let area2 = Int(dims2.width) * Int(dims2.height)
                return area1 < area2
            }
            
            // Target resolutions based on performance mode
            let targetMaxArea: Int32
            if effectiveMode == "low" {
                targetMaxArea = 640 * 480 // 480p
            } else {
                targetMaxArea = 1280 * 720 // 720p
            }
            
            // Find the best format that's <= target resolution
            var bestFormat: AVCaptureDevice.Format?
            var bestArea: Int32 = 0
            
            for format in availableFormats {
                let dims = format.formatDescription.dimensions
                let area = dims.width * dims.height
                
                if area <= targetMaxArea && area > bestArea {
                    // Prefer formats with 30fps or less for better performance
                    let frameRates = format.videoSupportedFrameRateRanges
                    if let frameRateRange = frameRates.first, frameRateRange.maxFrameRate <= 30.0 {
                        bestFormat = format
                        bestArea = area
                    } else if bestFormat == nil {
                        // Fallback to any format if no 30fps format found
                        bestFormat = format
                        bestArea = area
                    }
                }
            }
            
            // Apply the optimized format if found
            if let format = bestFormat {
                do {
                    try device.lockForConfiguration()
                    device.activeFormat = format
                    // Limit frame rate to 30fps for better performance
                    if let frameRateRange = format.videoSupportedFrameRateRanges.first {
                        let targetFrameRate = min(30.0, frameRateRange.maxFrameRate)
                        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(targetFrameRate))
                        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(targetFrameRate))
                        NSLog("Optimized format: %@, frame rate: %.1f fps", format.description, targetFrameRate)
                    }
                    device.unlockForConfiguration()
                } catch {
                    NSLog("Failed to configure optimized format: %@", error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Frame Rate Smoothing
    private func configurePreviewLayerSmoothing(previewLayer: AVCaptureVideoPreviewLayer, device: AVCaptureDevice) {
        let performanceMode = CPSettingsManager.shared.performanceMode
        
        // Auto-detect if needed
        var effectiveMode = performanceMode
        if performanceMode == "auto" {
            let processorCount = ProcessInfo.processInfo.processorCount
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            if processorCount <= 4 || physicalMemory < 8_000_000_000 {
                effectiveMode = "medium"
            } else {
                effectiveMode = "high"
            }
        }
        
        guard let connection = previewLayer.connection else { return }
        
        // Configure frame rate smoothing based on performance mode
        switch effectiveMode {
        case "low":
            // For low-performance systems, use aggressive frame rate limiting
            let targetFrameRate = 24.0 // 24fps for very smooth playback on slow systems
            
            if connection.isVideoMinFrameDurationSupported {
                let frameDuration = CMTime(value: 1, timescale: Int32(targetFrameRate))
                connection.videoMinFrameDuration = frameDuration
                NSLog("Set video min frame duration to %.1f fps for low-performance system", targetFrameRate)
            }
            
            if connection.isVideoMaxFrameDurationSupported {
                let frameDuration = CMTime(value: 1, timescale: Int32(targetFrameRate))
                connection.videoMaxFrameDuration = frameDuration
            }
            
            NSLog("Configured preview layer for smooth %0.1f fps on low-performance system", targetFrameRate)
            
        case "medium":
            // For slower systems, enable frame rate limiting and smoothing
            // Limit to 30fps or display refresh rate, whichever is lower
            let displayRefreshRate = Double(NSScreen.main?.maximumRefreshInterval ?? 60.0)
            let targetFrameRate = min(30.0, displayRefreshRate)
            
            // Configure connection for smooth frame delivery
            if connection.isVideoMinFrameDurationSupported {
                let frameDuration = CMTime(value: 1, timescale: Int32(targetFrameRate))
                connection.videoMinFrameDuration = frameDuration
                NSLog("Set video min frame duration to %.1f fps for smoothing", targetFrameRate)
            }
            
            // Enable frame dropping for consistent timing (drops frames rather than stuttering)
            if connection.isVideoMaxFrameDurationSupported {
                let frameDuration = CMTime(value: 1, timescale: Int32(targetFrameRate))
                connection.videoMaxFrameDuration = frameDuration
            }
            
            // Use enabled property to ensure connection is active
            if connection.isEnabled {
                // Connection is already enabled, which is good
            }
            
            NSLog("Configured preview layer for smooth %0.1f fps on %@ system", targetFrameRate, effectiveMode)
            
        case "high", "auto":
            // For high-performance systems, use native frame rate but still enable smoothing
            // Match display refresh rate for VSync
            if let screen = NSScreen.main {
                let refreshRate = Double(screen.maximumRefreshInterval)
                if refreshRate > 0 && connection.isVideoMinFrameDurationSupported {
                    let frameDuration = CMTime(value: 1, timescale: Int32(refreshRate))
                    connection.videoMinFrameDuration = frameDuration
                    NSLog("Matched preview frame rate to display refresh: %.1f fps", refreshRate)
                }
            }
        default:
            // Unknown mode, use medium settings as safe default
            let targetFrameRate = 30.0
            if connection.isVideoMinFrameDurationSupported {
                let frameDuration = CMTime(value: 1, timescale: Int32(targetFrameRate))
                connection.videoMinFrameDuration = frameDuration
            }
            if connection.isVideoMaxFrameDurationSupported {
                let frameDuration = CMTime(value: 1, timescale: Int32(targetFrameRate))
                connection.videoMaxFrameDuration = frameDuration
            }
            NSLog("Using default frame rate smoothing: %.1f fps", targetFrameRate)
        }
        
        // The preview layer automatically uses hardware acceleration
        // Connection is already configured for optimal performance
    }
    
    // MARK: - Audio Sample Rate Conversion
    private func getAACCompatibleSampleRate(inputRate: Double) -> Double {
        // AAC supports these sample rates: 8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000
        let supportedRates: [Double] = [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000]
        
        // If input rate is already supported, use it
        if supportedRates.contains(inputRate) {
            return inputRate
        }
        
        // Find the closest supported rate
        var closestRate = supportedRates[0]
        var smallestDifference = abs(inputRate - closestRate)
        
        for rate in supportedRates {
            let difference = abs(inputRate - rate)
            if difference < smallestDifference {
                smallestDifference = difference
                closestRate = rate
            }
        }
        
        // For high sample rates (like 96kHz), prefer 48kHz as it's the highest supported
        if inputRate >= 88200 {
            return 48000
        }
        
        return closestRate
    }
}


// MARK: - AVCaptureFileOutputRecordingDelegate
extension CPCaptureManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        NSLog("Video recording started to: %@", fileURL.path)
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = false
            self.detachRecordingAudioInput()
            // Record stop time for cooldown
            self.lastStopTime = Date()
            
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
                        self.delegate?.captureManager(self, didFinishRecordingTo: outputFileURL, error: nil)
                        return
                    } else {
                        // Remove empty file
                        try? fileManager.removeItem(at: outputFileURL)
                        NSLog("Removed empty file")
                    }
                }
                
                let message = "Video recording failed: \(error.localizedDescription)\n\nError code: \(nsError.code)"
                self.delegate?.captureManager(self, didFinishRecordingTo: outputFileURL, error: error)
                self.delegate?.captureManager(self, didEncounterError: error, message: message)
            } else {
                // Verify file was created
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: outputFileURL.path) {
                    let fileSize = (try? fileManager.attributesOfItem(atPath: outputFileURL.path)[.size] as? NSNumber)?.intValue ?? 0
                    NSLog("Video recording finished successfully: %@ (size: %d bytes)", outputFileURL.path, fileSize)
                    self.delegate?.captureManager(self, didFinishRecordingTo: outputFileURL, error: nil)
                } else {
                    NSLog("ERROR: Recording reported success but file does not exist: %@", outputFileURL.path)
                    let error = NSError(domain: "CPCaptureManager", code: -7, userInfo: [NSLocalizedDescriptionKey: "Recording completed but file was not created."])
                    self.delegate?.captureManager(self, didFinishRecordingTo: outputFileURL, error: error)
                    self.delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
                }
            }
        }
    }
}

