// Copyright H. Striepe - 2025
// Portions copyright Simon Guest - 2025

import AVFoundation
import Cocoa

// MARK: - QCCaptureManagerDelegate Protocol
protocol QCCaptureManagerDelegate: AnyObject {
    func captureManager(_ manager: QCCaptureManager, didDetectDevices devices: [AVCaptureDevice])
    func captureManager(_ manager: QCCaptureManager, didChangeDevice device: AVCaptureDevice, deviceIndex: Int)
    func captureManager(_ manager: QCCaptureManager, didStartRecordingTo url: URL)
    func captureManager(_ manager: QCCaptureManager, didFinishRecordingTo url: URL, error: Error?)
    func captureManager(_ manager: QCCaptureManager, didEncounterError error: Error, message: String)
    func captureManager(_ manager: QCCaptureManager, needsAudioDeviceUpdateFor videoDevice: AVCaptureDevice)
    func captureManager(_ manager: QCCaptureManager, needsSettingsApplication: Void)
    func captureManager(_ manager: QCCaptureManager, needsWindowTitleUpdate title: String)
    func captureManager(_ manager: QCCaptureManager, needsDeviceNameUpdate name: String)
    func captureManager(_ manager: QCCaptureManager, didChangeRecordingState isRecording: Bool)
}

// MARK: - QCCaptureManager Class
class QCCaptureManager: NSObject {
    
    // MARK: - Properties
    weak var delegate: QCCaptureManagerDelegate?
    
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
    
    // Dependencies (will be injected)
    var audioCaptureInput: AVCaptureDeviceInput? // Reference from audio manager (set by app delegate)
    var previewView: NSView? // Preview view for capture layer
    
    let defaultDeviceIndex: Int = 0
    
    // MARK: - Initialization
    override init() {
        super.init()
    }
    
    // MARK: - Device Detection
    func detectVideoDevices() {
        NSLog("Detecting video devices...")
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified)
        self.devices = discoverySession.devices
        
        if devices.isEmpty {
            let message = "Unfortunately, you don't appear to have any cameras connected. Goodbye for now!"
            let error = NSError(domain: "QCCaptureManager", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            delegate?.captureManager(self, didEncounterError: error, message: message)
            NSApp.terminate(nil)
        } else {
            NSLog("%d devices found", devices.count)
            delegate?.captureManager(self, didDetectDevices: devices)
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
        }
        
        // Create new session
        let session = AVCaptureSession()
        movieFileOutput = nil
        
        do {
            let deviceInput = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            
            if session.canAddInput(deviceInput) {
                session.addInput(deviceInput)
                self.input = deviceInput
            }
            
            // Add movie file output for video recording
            let movieOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
                self.movieFileOutput = movieOutput
            }
            
            session.commitConfiguration()
            
            // Setup preview layer
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
            previewLayer.connection?.isVideoMirrored = false
            
            if let previewView = previewView {
                previewView.layer = previewLayer
                previewView.layer?.backgroundColor = CGColor.black
            }
            
            self.captureSession = session
            self.captureLayer = previewLayer
            self.currentVideoDevice = device
            self.selectedDeviceIndex = deviceIndex
            
            // Notify delegate
            let windowTitle = String(format: "CapturePlay: [%@]", device.localizedName)
            delegate?.captureManager(self, needsWindowTitleUpdate: windowTitle)
            delegate?.captureManager(self, needsDeviceNameUpdate: device.localizedName)
            delegate?.captureManager(self, didChangeDevice: device, deviceIndex: deviceIndex)
            delegate?.captureManager(self, needsAudioDeviceUpdateFor: device)
            
            if !session.isRunning {
                session.startRunning()
            }
            
            delegate?.captureManager(self, needsSettingsApplication: ())
            
        } catch {
            NSLog("Error while opening device: %@", error.localizedDescription)
            let message = "Unfortunately, there was an error when trying to access the camera. Try again or select a different one."
            delegate?.captureManager(self, didEncounterError: error, message: message)
        }
    }
    
    // MARK: - Recording Management
    func startRecording(to captureDirectory: URL) {
        guard movieFileOutput != nil else {
            let error = NSError(domain: "QCCaptureManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Video recording is not available. Please ensure a video device is selected."])
            delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
            return
        }
        
        guard let session = captureSession else {
            let error = NSError(domain: "QCCaptureManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Capture session is not available."])
            delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
            return
        }
        
        // Ensure session is running
        if !session.isRunning {
            session.startRunning()
            // Give it a moment to establish connections
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.startVideoRecording(to: captureDirectory)
            }
        } else {
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
                let error = NSError(domain: "QCCaptureManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unable to access the capture directory."])
                delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
                return
            }
            startRecording(to: captureDir)
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
                let error = NSError(domain: "QCCaptureManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Cannot overwrite existing file: \(fileURL.lastPathComponent)"])
                delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
                return
            }
        }
        
        // Check if directory is writable
        let directoryPath = fileURL.deletingLastPathComponent().path
        if !fileManager.isWritableFile(atPath: directoryPath) {
            NSLog("ERROR: Directory is not writable: %@", directoryPath)
            let error = NSError(domain: "QCCaptureManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Directory is not writable: \(directoryPath)"])
            delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
            return
        }
        
        // Start recording
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        isRecording = true
        NSLog("Started video recording to: %@", fileURL.path)
        delegate?.captureManager(self, didStartRecordingTo: fileURL)
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
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension QCCaptureManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        NSLog("Video recording started to: %@", fileURL.path)
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
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
                    let error = NSError(domain: "QCCaptureManager", code: -7, userInfo: [NSLocalizedDescriptionKey: "Recording completed but file was not created."])
                    self.delegate?.captureManager(self, didFinishRecordingTo: outputFileURL, error: error)
                    self.delegate?.captureManager(self, didEncounterError: error, message: error.localizedDescription)
                }
            }
        }
    }
}

