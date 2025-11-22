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
    var captureSession: AVCaptureSession? {
        didSet {
            // Clear audio inputs/outputs when session changes to force recreation
            if captureSession !== oldValue {
                // Remove from old session if it still exists
                if let oldSession = oldValue {
                    if let oldInput = audioCaptureInput, oldSession.inputs.contains(oldInput) {
                        oldSession.beginConfiguration()
                        oldSession.removeInput(oldInput)
                        oldSession.commitConfiguration()
                    }
                    if let oldOutput = audioPreviewOutput, oldSession.outputs.contains(oldOutput) {
                        oldSession.beginConfiguration()
                        oldSession.removeOutput(oldOutput)
                        oldSession.commitConfiguration()
                    }
                }
                audioCaptureInput = nil
                audioPreviewOutput = nil
            }
        }
    }
    
    private(set) var audioCaptureInput: AVCaptureDeviceInput?
    private(set) var audioPreviewOutput: AVCaptureAudioPreviewOutput?
    private(set) var audioInputDevices: [AVCaptureDevice] = []
    private(set) var audioOutputDevices: [AudioOutputDeviceInfo] = []
    private(set) var selectedAudioInputUID: String?
    private(set) var selectedAudioOutputUID: String?
    
    // MARK: - Initialization
    init(captureSession: AVCaptureSession?) {
        self.captureSession = captureSession
    }
    
    // MARK: - Device Detection
    func detectAudioDevices() {
        refreshAudioDeviceLists()
        ensureAudioSelections()
        delegate?.audioManager(self, didDetectInputDevices: audioInputDevices)
        delegate?.audioManager(self, didDetectOutputDevices: audioOutputDevices)
        delegate?.audioManager(self, needsMenuUpdateForInput: audioInputDevices, selectedUID: selectedAudioInputUID)
        delegate?.audioManager(self, needsMenuUpdateForOutput: audioOutputDevices, selectedUID: selectedAudioOutputUID)
        
        // Apply configuration if session is available
        if captureSession != nil {
            applyAudioConfiguration()
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
            settings.setAudioInputUID(preferredInputUID)
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
            settings.setAudioInputUID(preferredInputUID)
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
    func applyAudioConfiguration() {
        guard let session = captureSession else { return }
        
        session.beginConfiguration()
        
        let desiredInputUID = selectedAudioInputUID
        
        // Remove existing audio input if it belongs to a different session or needs to be changed
        if let existingAudioInput = audioCaptureInput {
            // Check if the input is still in the current session
            if !session.inputs.contains(existingAudioInput) {
                audioCaptureInput = nil
            } else if desiredInputUID == nil || existingAudioInput.device.uniqueID != desiredInputUID {
                session.removeInput(existingAudioInput)
                audioCaptureInput = nil
            }
        }
        
        // Add new audio input if needed
        if audioCaptureInput == nil,
            let audioUID = desiredInputUID,
            let device = audioInputDevices.first(where: { $0.uniqueID == audioUID })
        {
            do {
                let newAudioInput = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(newAudioInput) {
                    session.addInput(newAudioInput)
                    audioCaptureInput = newAudioInput
                    delegate?.audioManager(self, didChangeInput: device)
                }
            } catch {
                NSLog("Unable to add audio input %@: %@", device.localizedName, error.localizedDescription)
            }
        }
        
        // Remove existing audio preview output if it belongs to a different session
        if let existingPreviewOutput = audioPreviewOutput {
            // Check if the output is still in the current session
            if !session.outputs.contains(existingPreviewOutput) {
                audioPreviewOutput = nil
            }
        }
        
        // Add audio preview output if needed
        if audioPreviewOutput == nil {
            let previewOutput = AVCaptureAudioPreviewOutput()
            let volume = CPSettingsManager.shared.audioVolume
            previewOutput.volume = CPSettingsManager.shared.isAudioMuted ? 0.0 : Float(volume)
            if session.canAddOutput(previewOutput) {
                session.addOutput(previewOutput)
                audioPreviewOutput = previewOutput
            }
        }
        
        session.commitConfiguration()
        
        updateAudioOutputRouting()
        
        if !session.isRunning {
            session.startRunning()
        }
        applyAudioMute()
    }
    
    private func updateAudioOutputRouting() {
        guard let preview = audioPreviewOutput else { return }
        let targetUID = selectedAudioOutputUID
        if preview.outputDeviceUniqueID != targetUID {
            preview.outputDeviceUniqueID = targetUID
            delegate?.audioManager(self, didChangeOutput: targetUID)
        }
        applyAudioMute()
    }
    
    // MARK: - Input/Output Selection
    func setAudioInput(uid: String) {
        selectedAudioInputUID = uid
        CPSettingsManager.shared.setAudioInputUID(uid)
        delegate?.audioManager(self, needsMenuUpdateForInput: audioInputDevices, selectedUID: selectedAudioInputUID)
        applyAudioConfiguration()
    }
    
    func setAudioOutput(uid: String) {
        selectedAudioOutputUID = uid
        CPSettingsManager.shared.setAudioOutputUID(uid)
        delegate?.audioManager(self, needsMenuUpdateForOutput: audioOutputDevices, selectedUID: selectedAudioOutputUID)
        updateAudioOutputRouting()
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
        }
    }
    
    // MARK: - Volume and Mute Management
    func applyAudioMute() {
        let muted = CPSettingsManager.shared.isAudioMuted
        let volume = CPSettingsManager.shared.audioVolume
        if let preview = audioPreviewOutput {
            preview.volume = muted ? 0.0 : Float(volume)
        }
        delegate?.audioManager(self, didChangeMuteState: muted)
    }
    
    func applyAudioVolume() {
        let muted = CPSettingsManager.shared.isAudioMuted
        let volume = CPSettingsManager.shared.audioVolume
        if let preview = audioPreviewOutput {
            preview.volume = muted ? 0.0 : Float(volume)
        }
        delegate?.audioManager(self, didChangeVolume: volume)
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
}

