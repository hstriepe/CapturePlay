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
    
    // MARK: - Initialization
    init() {}
    
    // MARK: - Device Detection
    func detectAudioDevices() {
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
        if preferredOutputUID.isEmpty,
            let defaultOutputUID = fetchDefaultAudioDeviceUID(for: kAudioDevicePropertyScopeOutput)
        {
            preferredOutputUID = defaultOutputUID
        }
        if preferredOutputUID.isEmpty {
            preferredOutputUID = audioOutputDevices.first?.uid ?? ""
        }
        if preferredOutputUID != settings.audioOutputUID {
            settings.setAudioOutputUID(preferredOutputUID)
        }
        if !preferredOutputUID.isEmpty,
            !audioOutputDevices.contains(where: { $0.uid == preferredOutputUID })
        {
            preferredOutputUID = audioOutputDevices.first?.uid ?? ""
            settings.setAudioOutputUID(preferredOutputUID)
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
                        NSLog("Cannot add audio input %@ to session", device.localizedName)
                    }
                } catch {
                    NSLog("Unable to add audio input %@: %@", device.localizedName, error.localizedDescription)
                }
            } else {
                NSLog("No audio input device available to add")
            }
        }
        
        if let existingPreviewOutput = audioPreviewOutput,
           !session.outputs.contains(existingPreviewOutput) {
            audioPreviewOutput = nil
        }
        
        if audioPreviewOutput == nil {
            let previewOutput = AVCaptureAudioPreviewOutput()
            let volume = CPSettingsManager.shared.audioVolume
            previewOutput.volume = CPSettingsManager.shared.isAudioMuted ? 0.0 : Float(volume)
            if session.canAddOutput(previewOutput) {
                session.addOutput(previewOutput)
                audioPreviewOutput = previewOutput
                NSLog("Added audio preview output, volume: %.2f, muted: %@", volume, CPSettingsManager.shared.isAudioMuted ? "yes" : "no")
            } else {
                NSLog("Cannot add audio preview output to session")
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
    
    private func _updateAudioOutputRouting() {
        guard let preview = audioPreviewOutput else {
            NSLog("Cannot update audio output routing: no preview output")
            return
        }
        let targetUID = selectedAudioOutputUID
        if preview.outputDeviceUniqueID != targetUID {
            preview.outputDeviceUniqueID = targetUID
            NSLog("Set audio output routing to: %@", targetUID ?? "default")
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.delegate?.audioManager(strongSelf, didChangeOutput: targetUID)
            }
        } else {
            NSLog("Audio output routing already set to: %@", targetUID ?? "default")
        }
        _applyAudioMute()
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
        selectedAudioOutputUID = uid
        CPSettingsManager.shared.setAudioOutputUID(uid)
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
    
    private func _applyAudioMute() {
        let muted = CPSettingsManager.shared.isAudioMuted
        let volume = CPSettingsManager.shared.audioVolume
        if let preview = audioPreviewOutput {
            preview.volume = muted ? 0.0 : Float(volume)
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
    
    private func _applyAudioVolume() {
        let muted = CPSettingsManager.shared.isAudioMuted
        let volume = CPSettingsManager.shared.audioVolume
        if let preview = audioPreviewOutput {
            preview.volume = muted ? 0.0 : Float(volume)
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
    private func fetchAudioOutputDevices() -> [AudioOutputDeviceInfo] {
        var results: [AudioOutputDeviceInfo] = []
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
            
            results.append(AudioOutputDeviceInfo(id: deviceID, uid: uid, name: name))
        }
        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        if status != noErr {
            return false
        }
        return dataSize > 0
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
}

