// Copyright H. Striepe ©2025

import AVFoundation
import Cocoa
import CoreAudio

// MARK: - AudioOutputDeviceInfo
struct AudioOutputDeviceInfo {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

// MARK: - CPAudioManagerDelegate Protocol
protocol CPAudioManagerDelegate: AnyObject {
    func audioManager(_ manager: CPAudioManager, didDetectInputDevices devices: [AVCaptureDevice])
    func audioManager(_ manager: CPAudioManager, didDetectOutputDevices devices: [AudioOutputDeviceInfo])
    func audioManager(_ manager: CPAudioManager, didChangeInput device: AVCaptureDevice?)
    func audioManager(_ manager: CPAudioManager, didChangeOutput deviceUID: String?)
    func audioManager(_ manager: CPAudioManager, needsMenuUpdateForInput devices: [AVCaptureDevice], selectedUID: String?)
    func audioManager(_ manager: CPAudioManager, needsMenuUpdateForOutput devices: [AudioOutputDeviceInfo], selectedUID: String?)
    func audioManager(_ manager: CPAudioManager, didChangeMuteState muted: Bool)
    func audioManager(_ manager: CPAudioManager, didChangeVolume volume: Float)
}

// MARK: - CPAudioManager Class
class CPAudioManager {
    
    // MARK: - Properties
    weak var delegate: CPAudioManagerDelegate?
    private let audioSession = AVCaptureSession()
    
    private(set) var audioCaptureInput: AVCaptureDeviceInput?
    private(set) var audioPreviewOutput: AVCaptureAudioPreviewOutput?
    private(set) var audioInputDevices: [AVCaptureDevice] = []
    private(set) var audioOutputDevices: [AudioOutputDeviceInfo] = []
    private(set) var selectedAudioInputUID: String?
    private(set) var selectedAudioOutputUID: String?
    private let sessionQueue = DispatchQueue(label: "org.captureplay.audio.session", qos: .userInitiated)
    private var deviceChangeListenerRef: UnsafeMutableRawPointer?
    private var isUpdatingDevices = false // Flag to prevent listener interference during updates
    
    func isCurrentlyUpdatingDevices() -> Bool {
        return isUpdatingDevices
    }
    
    func updateToSystemDefault() {
        guard CPSettingsManager.shared.followSystemOutput else { return }
        
        isUpdatingDevices = true
        defer { isUpdatingDevices = false }
        
        // Get current system default
        if let defaultOutputUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeOutput) {
            selectedAudioOutputUID = defaultOutputUID
            // Refresh device list to ensure the device is available
            refreshAudioDeviceLists()
            
            // Update routing
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.audioManager(self, needsMenuUpdateForOutput: self.audioOutputDevices, selectedUID: self.selectedAudioOutputUID)
            }
            
            sessionQueue.async { [weak self] in
                self?._updateAudioOutputRouting()
            }
        } else {
            // Fallback: refresh device list
            detectAudioDevices()
        }
    }
    
    // MARK: - Initialization
    init() {
        setupAudioDeviceChangeListener()
    }
    
    deinit {
        removeAudioDeviceChangeListener()
    }
    
    // MARK: - Device Detection
    func detectAudioDevices() {
        // Prevent recursive updates from device change listener
        guard !isUpdatingDevices else {
            NSLog("Device update already in progress, skipping")
            return
        }
        isUpdatingDevices = true
        defer { isUpdatingDevices = false }
        
        refreshAudioDeviceLists()
        ensureAudioSelections()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.audioManager(self, didDetectInputDevices: self.audioInputDevices)
            self.delegate?.audioManager(self, didDetectOutputDevices: self.audioOutputDevices)
            self.delegate?.audioManager(self, needsMenuUpdateForInput: self.audioInputDevices, selectedUID: self.selectedAudioInputUID)
            self.delegate?.audioManager(self, needsMenuUpdateForOutput: self.audioOutputDevices, selectedUID: self.selectedAudioOutputUID)
        }
        
        sessionQueue.async { [weak self] in
            self?._applyAudioConfiguration()
        }
    }
    
    private func refreshAudioDeviceLists() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        audioInputDevices = discoverySession.devices.sorted {
            $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending
        }
        audioOutputDevices = fetchAudioOutputDevices()
    }
    
    private func ensureAudioSelections() {
        let settings = CPSettingsManager.shared
        let hasUserSelection = !settings.audioInputUID.isEmpty
        
        // Determine preferred input UID
        var preferredInputUID = settings.audioInputUID
        if preferredInputUID.isEmpty {
            // Try to get from linked video device (will be set via updatePreferredInputFromVideo)
            preferredInputUID = ""
        }
        if preferredInputUID.isEmpty,
            let defaultInputUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeInput)
        {
            preferredInputUID = defaultInputUID
        }
        if preferredInputUID.isEmpty {
            // Prefer built-in microphones over Continuity Camera devices
            let preferredDevice = audioInputDevices.first { device in
                if #available(macOS 13.0, *) {
                    return device.deviceType != .continuityCamera
                } else {
                    return true
                }
            } ?? audioInputDevices.first
            preferredInputUID = preferredDevice?.uniqueID ?? ""
        }
        if preferredInputUID != settings.audioInputUID {
            if !hasUserSelection {
                settings.setAudioInputUID(preferredInputUID)
            }
        }
        if !preferredInputUID.isEmpty,
            !audioInputDevices.contains(where: { $0.uniqueID == preferredInputUID })
        {
            // Prefer built-in microphones over Continuity Camera devices
            let preferredDevice = audioInputDevices.first { device in
                if #available(macOS 13.0, *) {
                    return device.deviceType != .continuityCamera
                } else {
                    return true
                }
            } ?? audioInputDevices.first
            preferredInputUID = preferredDevice?.uniqueID ?? ""
            if !hasUserSelection || settings.audioInputUID.isEmpty {
                settings.setAudioInputUID(preferredInputUID)
            }
        }
        selectedAudioInputUID = preferredInputUID.isEmpty ? nil : preferredInputUID
        
        // Determine preferred output UID
        var preferredOutputUID = settings.audioOutputUID
        
        // Handle "Follow System Output" mode
        if settings.followSystemOutput {
            // Always use system default when following
            if let defaultOutputUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeOutput) {
                preferredOutputUID = defaultOutputUID
            } else {
                preferredOutputUID = audioOutputDevices.first?.uid ?? ""
            }
        } else if preferredOutputUID == "SYSTEM_DEFAULT" {
            // Legacy: if UID is SYSTEM_DEFAULT but followSystemOutput is false, enable it
            settings.setFollowSystemOutput(true)
            if let defaultOutputUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeOutput) {
                preferredOutputUID = defaultOutputUID
            } else {
                preferredOutputUID = audioOutputDevices.first?.uid ?? ""
            }
        } else if preferredOutputUID.isEmpty,
            let defaultOutputUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeOutput)
        {
            preferredOutputUID = defaultOutputUID
        }
        
        if preferredOutputUID.isEmpty {
            preferredOutputUID = audioOutputDevices.first?.uid ?? ""
        }
        
        // Update settings if changed (but preserve followSystemOutput setting)
        if preferredOutputUID != settings.audioOutputUID && !settings.followSystemOutput {
            settings.setAudioOutputUID(preferredOutputUID)
        }
        
        if !preferredOutputUID.isEmpty,
            !audioOutputDevices.contains(where: { $0.uid == preferredOutputUID })
        {
            if settings.followSystemOutput {
                // If following system, get the current default
                if let defaultOutputUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeOutput) {
                    preferredOutputUID = defaultOutputUID
                } else {
            preferredOutputUID = audioOutputDevices.first?.uid ?? ""
                }
            } else {
            preferredOutputUID = audioOutputDevices.first?.uid ?? ""
            }
            if !settings.followSystemOutput {
            settings.setAudioOutputUID(preferredOutputUID)
            }
        }
        selectedAudioOutputUID = preferredOutputUID.isEmpty ? nil : preferredOutputUID
    }
    
    // MARK: - Audio Configuration
    private func _applyAudioConfiguration(force: Bool = false) {
        let session = audioSession
        
        let desiredInputUID = selectedAudioInputUID
        let currentInputUID = audioCaptureInput?.device.uniqueID
        let needsInputUpdate: Bool = {
            if force {
                // Force update if requested
                return true
            }
            if let desired = desiredInputUID {
                return audioCaptureInput == nil || currentInputUID != desired
            } else {
                // If no selection but we have devices available and no input, we should add one
                return audioCaptureInput == nil && !audioInputDevices.isEmpty
            }
        }()
        
        // Check if output needs update
        let needsOutputUpdate = force || audioPreviewOutput == nil
        
        // Skip session reconfiguration if nothing needs to change, but still ensure session is running
        if !force && !needsInputUpdate && !needsOutputUpdate {
            // Just update routing and mute state without touching session
            _updateAudioOutputRouting()
            _applyAudioMute()
            // Ensure session is running even if nothing changed
            if !session.isRunning {
                session.startRunning()
            }
            return
        }
        
        session.beginConfiguration()
        
        if needsInputUpdate {
            if let existingAudioInput = audioCaptureInput,
               session.inputs.contains(existingAudioInput) {
                session.removeInput(existingAudioInput)
                audioCaptureInput = nil
            }
            
            // Try to add the desired input, or fall back to first available device
            var deviceToAdd: AVCaptureDevice?
            if let audioUID = desiredInputUID,
               let device = audioInputDevices.first(where: { $0.uniqueID == audioUID }) {
                deviceToAdd = device
            } else if let firstDevice = audioInputDevices.first {
                // Fall back to first available device if no selection
                deviceToAdd = firstDevice
                selectedAudioInputUID = firstDevice.uniqueID
                NSLog("No audio input selected, using first available: %@", firstDevice.localizedName)
            }
            
            if let device = deviceToAdd {
                // Verify device is still available
                guard device.isConnected && !device.isSuspended else {
                    NSLog("ERROR: Audio input device '%@' is no longer available (connected: %@, suspended: %@)", 
                          device.localizedName, device.isConnected ? "yes" : "no", device.isSuspended ? "yes" : "no")
                    // Try to find an alternative device
                    if let alternativeDevice = audioInputDevices.first(where: { $0.isConnected && !$0.isSuspended && $0.uniqueID != device.uniqueID }) {
                        NSLog("Attempting to use alternative device: %@", alternativeDevice.localizedName)
                        selectedAudioInputUID = alternativeDevice.uniqueID
                        // Recursively try with alternative (but prevent infinite loop)
                        if needsInputUpdate {
                            return
                        }
                    }
                    return
                }
                
                do {
                    let newAudioInput = try AVCaptureDeviceInput(device: device)
                    if session.canAddInput(newAudioInput) {
                        session.addInput(newAudioInput)
                        audioCaptureInput = newAudioInput
                        NSLog("Added audio input: %@", device.localizedName)
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.delegate?.audioManager(self, didChangeInput: device)
                        }
                    } else {
                        NSLog("ERROR: Cannot add audio input '%@' to session - session may be in use", device.localizedName)
                    }
                } catch {
                    NSLog("ERROR: Unable to add audio input '%@': %@", device.localizedName, error.localizedDescription)
                    // Try to find an alternative device
                    if let alternativeDevice = audioInputDevices.first(where: { $0.uniqueID != device.uniqueID && $0.isConnected && !$0.isSuspended }) {
                        NSLog("Attempting to use alternative device: %@", alternativeDevice.localizedName)
                        selectedAudioInputUID = alternativeDevice.uniqueID
                    }
                }
            } else {
                NSLog("WARNING: No audio input device available to add")
            }
        }
        
        if let existingPreviewOutput = audioPreviewOutput,
           !session.outputs.contains(existingPreviewOutput) {
            audioPreviewOutput = nil
        }
        
        if audioPreviewOutput == nil {
            let previewOutput = AVCaptureAudioPreviewOutput()
            let settings = CPSettingsManager.shared
            let volume = settings.audioVolume
            // Ensure minimum volume of 0.01 to prevent silence (unless muted)
            let effectiveVolume = settings.isAudioMuted ? 0.0 : max(0.01, Float(volume))
            previewOutput.volume = effectiveVolume
            if session.canAddOutput(previewOutput) {
                session.addOutput(previewOutput)
                audioPreviewOutput = previewOutput
                NSLog("Added audio preview output, volume: %.2f (requested: %.2f), muted: %@", 
                      effectiveVolume, volume, settings.isAudioMuted ? "yes" : "no")
            } else {
                NSLog("ERROR: Cannot add audio preview output to session")
            }
        }
        
        session.commitConfiguration()
        
        // Log session state
        NSLog("Audio session configured - input: %@, output: %@, running: %@", 
              audioCaptureInput != nil ? audioCaptureInput!.device.localizedName : "none",
              audioPreviewOutput != nil ? "yes" : "no",
              session.isRunning ? "yes" : "no")
        
        if !session.isRunning {
            session.startRunning()
            NSLog("Audio session started")
        }
        
        _updateAudioOutputRouting()
        _applyAudioMute()
        
        // Log final state
        NSLog("Audio session final state - running: %@, has input: %@, has output: %@",
              session.isRunning ? "yes" : "no",
              audioCaptureInput != nil ? "yes" : "no",
              audioPreviewOutput != nil ? "yes" : "no")
    }
    
    /// Updates the audio output routing to the selected device.
    /// 
    /// This method:
    /// 1. Verifies the target device is still available (handles device disconnection)
    /// 2. Falls back to system default or first available device if target is unavailable
    /// 3. Sets the routing on the AVCaptureAudioPreviewOutput
    /// 4. Ensures volume is properly applied (immediately and after a short delay)
    ///    The delay allows the routing change to complete before volume is set
    private func _updateAudioOutputRouting() {
        guard let preview = audioPreviewOutput else {
            NSLog("ERROR: Cannot update audio output routing - no preview output available")
            return
        }
        
        let targetUID = selectedAudioOutputUID
        
        // Verify target device is still available
        if let targetUID = targetUID, !audioOutputDevices.contains(where: { $0.uid == targetUID }) {
            NSLog("WARNING: Target output device '%@' is no longer available, falling back to default", targetUID)
            // Fallback to system default or first available device
            if let defaultUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeOutput) {
                selectedAudioOutputUID = defaultUID
            } else if let firstDevice = audioOutputDevices.first {
                selectedAudioOutputUID = firstDevice.uid
                NSLog("Using first available device: %@", firstDevice.name)
            } else {
                NSLog("ERROR: No audio output devices available")
                return
            }
        }
        
        let finalUID = selectedAudioOutputUID
        
        // Log device information for USB DACs to help diagnose muffled audio
        if let targetUID = finalUID,
           let deviceInfo = audioOutputDevices.first(where: { $0.uid == targetUID }) {
            let isUSB = isUSBDevice(deviceID: deviceInfo.id)
            if isUSB {
                let dacSampleRate = fetchAudioDeviceSampleRate(deviceID: deviceInfo.id)
                var inputSampleRate: Double = 0
                if let audioInput = audioCaptureInput {
                    let formatDesc = audioInput.device.activeFormat.formatDescription
                    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                    if let asbd = asbd?.pointee {
                        inputSampleRate = Double(asbd.mSampleRate)
                    }
                }
                NSLog("USB DAC detected: %@ (UID: %@, DAC Sample Rate: %.0f Hz, Input Sample Rate: %.0f Hz)", 
                      deviceInfo.name, targetUID, dacSampleRate, inputSampleRate)
                if inputSampleRate > 0 && abs(dacSampleRate - inputSampleRate) > 0.1 {
                    NSLog("WARNING: Sample rate mismatch between input (%.0f Hz) and USB DAC (%.0f Hz) may cause audio quality issues", 
                          inputSampleRate, dacSampleRate)
                }
            }
        }
        
        if preview.outputDeviceUniqueID != finalUID {
            preview.outputDeviceUniqueID = finalUID
            NSLog("Set audio output routing to: %@", finalUID ?? "default")
            
            // For USB DACs, use a longer delay to allow proper initialization
            // This helps prevent muffled audio caused by premature routing
            let deviceInfo = finalUID.flatMap { uid in audioOutputDevices.first(where: { $0.uid == uid }) }
            let isUSB = deviceInfo.map { isUSBDevice(deviceID: $0.id) } ?? false
            let delay = isUSB ? 0.2 : 0.1 // Longer delay for USB DACs
            
            // Ensure volume is properly set after routing change
            // Small delay to allow routing to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.sessionQueue.async {
                    // Re-apply volume to ensure it's set correctly on the new device
                    self._applyAudioMute()
                    
                    // For USB DACs, apply volume again after another brief delay
                    // This helps ensure the DAC is fully initialized
                    if isUSB {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                            guard let self = self else { return }
                            self.sessionQueue.async {
                                self._applyAudioMute()
                            }
                        }
                    }
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.delegate?.audioManager(strongSelf, didChangeOutput: finalUID)
            }
        } else {
            NSLog("Audio output routing already set to: %@", finalUID ?? "default")
        }
        
        // Apply volume immediately (will be re-applied after delay for safety)
        _applyAudioMute()
    }
    
    /// Checks if an audio device is a USB device
    private func isUSBDevice(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let transportStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &transportType
        )
        if transportStatus == noErr {
            // USB transport type is 'usbf' = 0x75736266
            let usbType: UInt32 = 0x75736266 // 'usbf'
            return transportType == usbType
        }
        return false
    }
    
    /// Fetches the current sample rate of an audio device
    private func fetchAudioDeviceSampleRate(deviceID: AudioDeviceID) -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 44100.0
        var dataSize = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &sampleRate
        )
        if status == noErr {
            return Double(sampleRate)
        }
        return 44100.0 // Default fallback
    }
    
    // MARK: - Input/Output Selection
    func setAudioInput(uid: String) {
        selectedAudioInputUID = uid
        CPSettingsManager.shared.setAudioInputUID(uid)
        delegate?.audioManager(self, needsMenuUpdateForInput: audioInputDevices, selectedUID: selectedAudioInputUID)
        sessionQueue.async { [weak self] in
            self?._applyAudioConfiguration()
        }
    }
    
    func setAudioOutput(uid: String) {
        // Prevent device change listener from interfering
        isUpdatingDevices = true
        defer { isUpdatingDevices = false }
        
        let settings = CPSettingsManager.shared
        
        // Handle "Follow System Output" mode
        if uid == "SYSTEM_DEFAULT" {
            settings.setFollowSystemOutput(true)
            // Get current system default
            if let defaultOutputUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeOutput) {
                selectedAudioOutputUID = defaultOutputUID
                NSLog("Following system output: %@", defaultOutputUID)
            } else {
                // Fallback to first available device
                if let firstDevice = audioOutputDevices.first {
                    selectedAudioOutputUID = firstDevice.uid
                    NSLog("WARNING: System default not available, using first device: %@", firstDevice.name)
                } else {
                    NSLog("ERROR: No audio output devices available")
                    return
                }
            }
        } else {
            settings.setFollowSystemOutput(false)
            
            // Verify the requested device is still available
            if !audioOutputDevices.contains(where: { $0.uid == uid }) {
                NSLog("WARNING: Requested output device '%@' is no longer available", uid)
                // Fallback to system default or first available
                if let defaultOutputUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeOutput) {
                    selectedAudioOutputUID = defaultOutputUID
                    NSLog("Using system default instead: %@", defaultOutputUID)
                } else if let firstDevice = audioOutputDevices.first {
                    selectedAudioOutputUID = firstDevice.uid
                    NSLog("Using first available device instead: %@", firstDevice.name)
                } else {
                    NSLog("ERROR: No audio output devices available")
                    return
                }
            } else {
        selectedAudioOutputUID = uid
                settings.setAudioOutputUID(uid)
            }
        }
        
        delegate?.audioManager(self, needsMenuUpdateForOutput: audioOutputDevices, selectedUID: selectedAudioOutputUID)
        sessionQueue.async { [weak self] in
            self?._updateAudioOutputRouting()
        }
    }
    
    func ensureAudioSessionConfigured() {
        // Ensure audio devices are detected if not already done
        if audioInputDevices.isEmpty {
            refreshAudioDeviceLists()
            ensureAudioSelections()
            // Update menus if devices were just detected
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.audioManager(self, didDetectInputDevices: self.audioInputDevices)
                self.delegate?.audioManager(self, didDetectOutputDevices: self.audioOutputDevices)
                self.delegate?.audioManager(self, needsMenuUpdateForInput: self.audioInputDevices, selectedUID: self.selectedAudioInputUID)
                self.delegate?.audioManager(self, needsMenuUpdateForOutput: self.audioOutputDevices, selectedUID: self.selectedAudioOutputUID)
            }
        } else {
            // Refresh selections even if devices are already detected
            ensureAudioSelections()
        }
        // Force audio session configuration (even if it thinks nothing changed)
        sessionQueue.async { [weak self] in
            self?._applyAudioConfiguration(force: true)
        }
    }
    
    func updatePreferredInputFromVideo(videoDevice: AVCaptureDevice) {
        let settings = CPSettingsManager.shared
        guard settings.audioInputUID.isEmpty else { return }
        
        // Don't auto-select audio from Continuity Camera - prefer other audio devices
        if #available(macOS 13.0, *) {
            if videoDevice.deviceType == .continuityCamera {
                NSLog("Skipping audio auto-selection for Continuity Camera '%@'", videoDevice.localizedName)
                return
            }
        }
        
        if let linkedAudio = videoDevice.linkedDevices.first(where: { $0.hasMediaType(.audio) }) {
            NSLog("Auto-selecting linked audio device '%@' for video device '%@'", linkedAudio.localizedName, videoDevice.localizedName)
            settings.setAudioInputUID(linkedAudio.uniqueID)
            selectedAudioInputUID = linkedAudio.uniqueID
            delegate?.audioManager(self, needsMenuUpdateForInput: audioInputDevices, selectedUID: selectedAudioInputUID)
            sessionQueue.async { [weak self] in
                self?._applyAudioConfiguration()
            }
        }
    }
    
    // MARK: - Volume and Mute Management
    func applyAudioMute() {
        sessionQueue.async { [weak self] in
            self?._applyAudioMute()
        }
    }
    
    /// Applies mute state and volume to the audio preview output.
    /// 
    /// Implements a minimum volume threshold (0.01) to prevent accidental silence.
    /// This ensures that even if the user sets volume to 0, there's still a minimal
    /// audio level (unless explicitly muted).
    private func _applyAudioMute() {
        let settings = CPSettingsManager.shared
        let muted = settings.isAudioMuted
        let volume = settings.audioVolume
        
        guard let preview = audioPreviewOutput else {
            NSLog("WARNING: Cannot apply mute/volume - no preview output available")
            return
        }
        
        // Ensure minimum volume of 0.01 to prevent silence (unless muted)
        let effectiveVolume = muted ? 0.0 : max(0.01, Float(volume))
        preview.volume = effectiveVolume
        
        // Log volume application for USB DACs to help diagnose muffled audio
        if let outputUID = selectedAudioOutputUID,
           let deviceInfo = audioOutputDevices.first(where: { $0.uid == outputUID }),
           isUSBDevice(deviceID: deviceInfo.id) {
            NSLog("USB DAC volume applied: %.2f (requested: %.2f, muted: %@)", 
                  effectiveVolume, volume, muted ? "yes" : "no")
        }
        
        if effectiveVolume != Float(volume) && !muted {
            NSLog("Applied minimum volume threshold: %.2f (requested: %.2f)", effectiveVolume, volume)
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.delegate?.audioManager(strongSelf, didChangeMuteState: muted)
        }
    }
    
    func applyAudioVolume() {
        sessionQueue.async { [weak self] in
            self?._applyAudioVolume()
        }
    }
    
    /// Applies volume to the audio preview output.
    /// 
    /// Implements a minimum volume threshold (0.01) to prevent accidental silence.
    /// This ensures that even if the user sets volume to 0, there's still a minimal
    /// audio level (unless explicitly muted).
    private func _applyAudioVolume() {
        let settings = CPSettingsManager.shared
        let muted = settings.isAudioMuted
        let volume = settings.audioVolume
        
        guard let preview = audioPreviewOutput else {
            NSLog("WARNING: Cannot apply volume - no preview output available")
            return
        }
        
        // Ensure minimum volume of 0.01 to prevent silence (unless muted)
        let effectiveVolume = muted ? 0.0 : max(0.01, Float(volume))
        preview.volume = effectiveVolume
        
        if effectiveVolume != Float(volume) && !muted {
            NSLog("Applied minimum volume threshold: %.2f (requested: %.2f)", effectiveVolume, volume)
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.delegate?.audioManager(strongSelf, didChangeVolume: volume)
        }
    }
    
    func toggleMute() {
        let newValue = !CPSettingsManager.shared.isAudioMuted
        CPSettingsManager.shared.setAudioMuted(newValue)
        applyAudioMute()
    }
    
    func setVolume(_ volume: Float) {
        CPSettingsManager.shared.setAudioVolume(volume)
        applyAudioVolume()
    }
    
    // MARK: - CoreAudio Integration
    
    /// Fetches and deduplicates audio output devices from CoreAudio.
    /// 
    /// This method handles several complexities:
    /// 1. **Deduplication by UID**: Multiple device IDs may share the same UID (e.g., different profiles)
    /// 2. **Bluetooth device handling**: Bluetooth devices often appear multiple times with different profiles
    ///    (A2DP for audio, HFP for calls). We prefer devices with active output streams.
    /// 3. **Device selection preservation**: The currently selected device is always included, even if
    ///    a "better" version is found, to prevent unexpected switching.
    /// 4. **Stream-based prioritization**: Devices with active output streams are preferred over those without.
    ///
    /// - Returns: Array of unique audio output devices, sorted alphabetically by name
    private func fetchAudioOutputDevices() -> [AudioOutputDeviceInfo] {
        var deviceMap: [String: AudioOutputDeviceInfo] = [:] // Deduplicate by UID
        var bluetoothDevicesByName: [String: AudioOutputDeviceInfo] = [:] // Track Bluetooth by name for deduplication
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
            
            let deviceInfo = AudioOutputDeviceInfo(id: deviceID, uid: uid, name: name)
            let isBluetooth = isBluetoothDevice(deviceID: deviceID)
            let hasStreams = deviceHasActiveOutputStreams(deviceID: deviceID)
            
            // Always add to deviceMap by UID (deduplicate by preferring devices with streams)
            if let existing = deviceMap[uid] {
                let existingHasStreams = deviceHasActiveOutputStreams(deviceID: existing.id)
                
                // Prefer device with active streams, or keep currently selected device
                if hasStreams && !existingHasStreams {
                    deviceMap[uid] = deviceInfo
                } else if selectedAudioOutputUID == uid && existing.id == deviceID {
                    // Keep currently selected device
                } else if selectedAudioOutputUID == uid && hasStreams {
                    // Selected UID but different device ID - prefer one with streams
                    deviceMap[uid] = deviceInfo
                }
            } else {
                deviceMap[uid] = deviceInfo
            }
            
            // For Bluetooth devices, track by name to help with deduplication
            if isBluetooth {
                if let existingByName = bluetoothDevicesByName[name] {
                    let existingHasStreams = deviceHasActiveOutputStreams(deviceID: existingByName.id)
                    
                    // Prefer device with active streams, or the one that's currently selected
                    if hasStreams && !existingHasStreams {
                        bluetoothDevicesByName[name] = deviceInfo
                    } else if selectedAudioOutputUID == uid {
                        // Prefer selected device
                        bluetoothDevicesByName[name] = deviceInfo
                    } else if existingByName.uid == selectedAudioOutputUID {
                        // Keep existing if it's the selected one
                    } else if !hasStreams && existingHasStreams {
                        // Keep existing if it has streams and new doesn't
                    }
                } else {
                    bluetoothDevicesByName[name] = deviceInfo
                }
            }
        }
        
        // Build final list: include all unique UIDs, but for Bluetooth with duplicate names, prefer the best one
        var finalResults: [AudioOutputDeviceInfo] = []
        var seenBluetoothNames: Set<String> = []
        var addedUIDs: Set<String> = []
        
        // First, ensure selected device is included
        if let selectedUID = selectedAudioOutputUID,
           let selectedDevice = deviceMap[selectedUID] {
            finalResults.append(selectedDevice)
            addedUIDs.insert(selectedUID)
            if isBluetoothDevice(deviceID: selectedDevice.id) {
                seenBluetoothNames.insert(selectedDevice.name)
            }
        }
        
        // Process all devices
        for device in deviceMap.values {
            // Skip if already added (e.g., as selected device)
            if addedUIDs.contains(device.uid) {
                continue
            }
            
            let isBluetooth = isBluetoothDevice(deviceID: device.id)
            
            if isBluetooth {
                // For Bluetooth, if we've seen this name before, prefer the one from bluetoothDevicesByName
                if seenBluetoothNames.contains(device.name) {
                    // Check if there's a better version in bluetoothDevicesByName
                    if let betterVersion = bluetoothDevicesByName[device.name],
                       !addedUIDs.contains(betterVersion.uid),
                       betterVersion.uid != device.uid {
                        // Use the better version (has streams or is selected)
                        finalResults.append(betterVersion)
                        addedUIDs.insert(betterVersion.uid)
                    }
                    // Skip this device since we've already handled this name
                    continue
                }
                
                // Check if there's a better version in bluetoothDevicesByName
                if let betterVersion = bluetoothDevicesByName[device.name],
                   betterVersion.uid != device.uid {
                    // Use the better version (has streams or is selected)
                    finalResults.append(betterVersion)
                    addedUIDs.insert(betterVersion.uid)
                    seenBluetoothNames.insert(device.name)
                } else {
                    // Use this device
                    finalResults.append(device)
                    addedUIDs.insert(device.uid)
                    seenBluetoothNames.insert(device.name)
                }
            } else {
                // For non-Bluetooth, include all unique UIDs
                finalResults.append(device)
                addedUIDs.insert(device.uid)
            }
        }
        
        NSLog("Total audio output devices: %d (after deduplication)", finalResults.count)
        for device in finalResults {
            let isSelected = device.uid == selectedAudioOutputUID
            NSLog("  - %@ (UID: %@)%@", device.name, device.uid, isSelected ? " [SELECTED]" : "")
        }
        return finalResults.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    
    private func isBluetoothDevice(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let transportStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &transportType
        )
        if transportStatus == noErr {
            let bluetoothType: UInt32 = 0x626C7565 // 'blue'
            let bluetoothLEType: UInt32 = 0x626C6C65 // 'blle'
            return transportType == bluetoothType || transportType == bluetoothLEType
        }
        return false
    }
    
    private func deviceHasActiveOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
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
        // For output scope, we need to be strict - only include devices that actually support output
        if scope == kAudioDevicePropertyScopeOutput {
            // Check if device has OUTPUT streams
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
            var outputDataSize: UInt32 = 0
            let outputStatus = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &outputDataSize)
            
            // Check if device has INPUT streams
            propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
            var inputDataSize: UInt32 = 0
            let inputStatus = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &inputDataSize)
            
            // Exclude devices that ONLY have input (no output)
            if inputStatus == noErr && inputDataSize > 0 && (outputStatus != noErr || outputDataSize == 0) {
                // Device has input but no output - exclude from output list
            return false
        }
            
            // Include if it has output streams
            if outputStatus == noErr && outputDataSize > 0 {
                return true
            }
            
            // Check stream configuration for output
            propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            outputDataSize = 0
            let configStatus = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &outputDataSize)
            if configStatus == noErr && outputDataSize > 0 {
                return true
            }
            
            // For Bluetooth devices, check transport type and include if Bluetooth (even if streams not yet available)
            propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var transportType: UInt32 = 0
            var dataSize = UInt32(MemoryLayout<UInt32>.size)
            let transportStatus = AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                &transportType
            )
            if transportStatus == noErr {
                // Check for Bluetooth transport types
                let bluetoothType: UInt32 = 0x626C7565 // 'blue'
                let bluetoothLEType: UInt32 = 0x626C6C65 // 'blle'
                if transportType == bluetoothType || transportType == bluetoothLEType {
                    // It's a Bluetooth device - verify it's not input-only
                    // We already checked above, so if we got here, it either has output or is unknown
                    // Include it if it has a valid UID
                    if copyAudioDevicePropertyString(
                        deviceID: deviceID,
                        selector: kAudioDevicePropertyDeviceUID,
                        scope: kAudioObjectPropertyScopeGlobal
                    ) != nil {
                        return true
                    }
                }
            }
        }
        
        return false
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
        
        // Allocate memory for CFString reference
        var cfString: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        // Use withUnsafeMutableBytes to get a raw pointer without triggering the warning
        let status = withUnsafeMutableBytes(of: &cfString) { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return OSStatus(-1)
            }
            return withUnsafeMutablePointer(to: &dataSize) { dataSizePointer in
                AudioObjectGetPropertyData(
                    deviceID,
                    &propertyAddress,
                    0,
                    nil,
                    dataSizePointer,
                    baseAddress
                )
            }
        }
        
        if status != noErr {
            return nil
        }
        return cfString?.takeRetainedValue() as String?
    }
    
    // MARK: - Accessors
    func getAudioCaptureInput() -> AVCaptureDeviceInput? {
        return audioCaptureInput
    }
    
    func getAudioPreviewOutput() -> AVCaptureAudioPreviewOutput? {
        return audioPreviewOutput
    }
    
    func makeRecordingInput() -> AVCaptureDeviceInput? {
        guard let audioUID = selectedAudioInputUID else {
            return nil
        }
        
        let device: AVCaptureDevice?
        if let cached = audioInputDevices.first(where: { $0.uniqueID == audioUID }) {
            device = cached
        } else {
            device = AVCaptureDevice.devices(for: .audio).first(where: { $0.uniqueID == audioUID })
        }
        
        guard let targetDevice = device else {
            NSLog("Unable to locate audio device with UID %@", audioUID)
            return nil
        }
        do {
            return try AVCaptureDeviceInput(device: targetDevice)
        } catch {
            NSLog("Unable to build recording audio input for %@: %@", targetDevice.localizedName, error.localizedDescription)
            return nil
        }
    }
    
    // MARK: - Audio Device Change Monitoring
    private func setupAudioDeviceChangeListener() {
        // Store self reference for the callback
        deviceChangeListenerRef = Unmanaged.passUnretained(self).toOpaque()
        
        // Register listener for device list changes
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            audioDeviceChangeCallback,
            deviceChangeListenerRef
        )
        
        if status != noErr {
            NSLog("Failed to register audio device change listener: %d", status)
        } else {
            NSLog("Registered audio device change listener")
        }
        
        // Also listen for default output device changes
        propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let defaultStatus = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            audioDeviceChangeCallback,
            deviceChangeListenerRef
        )
        
        if defaultStatus != noErr {
            NSLog("Failed to register default output device change listener: %d", defaultStatus)
        }
    }
    
    private func removeAudioDeviceChangeListener() {
        guard deviceChangeListenerRef != nil else { return }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            audioDeviceChangeCallback,
            deviceChangeListenerRef
        )
        
        propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            audioDeviceChangeCallback,
            deviceChangeListenerRef
        )
        
        deviceChangeListenerRef = nil
    }
}

// MARK: - C Callback for Audio Device Changes
private func audioDeviceChangeCallback(
    inObjectID: AudioObjectID,
    inNumberAddresses: UInt32,
    inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = inClientData else { return noErr }
    let manager = Unmanaged<CPAudioManager>.fromOpaque(clientData).takeUnretainedValue()
    
    // Don't trigger updates if we're already updating (prevents interference with selection)
    guard !manager.isCurrentlyUpdatingDevices() else {
        return noErr
    }
    
    // Check if this is a device list change
    for i in 0..<Int(inNumberAddresses) {
        let address = inAddresses[i]
        if address.mSelector == kAudioHardwarePropertyDevices {
            // Devices changed, refresh the list after a short delay to avoid rapid updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                manager.detectAudioDevices()
            }
            break
        } else if address.mSelector == kAudioHardwarePropertyDefaultOutputDevice {
            // Default output device changed
            let settings = CPSettingsManager.shared
            if settings.followSystemOutput {
                // If following system output, update to new default immediately
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    manager.updateToSystemDefault()
                }
            } else {
                // Just refresh the list
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    manager.detectAudioDevices()
                }
            }
            break
        }
    }
    
    return noErr
}

