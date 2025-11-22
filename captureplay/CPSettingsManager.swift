// Copyright H. Striepe ©2025

import AVFoundation
import Cocoa

class CPSettingsManager {
    // MARK: - Properties
    private(set) var isMirrored: Bool = false
    private(set) var isUpsideDown: Bool = false
    private(set) var isBorderless: Bool = false
    private(set) var isAspectRatioFixed: Bool = false
    private(set) var position: Int = 0
    private(set) var deviceName: String = "-"
    private(set) var savedDeviceName: String = "-"
    private(set) var preventDisplaySleep: Bool = false
    private(set) var audioInputUID: String = ""
    private(set) var audioOutputUID: String = ""
    private(set) var isAudioMuted: Bool = false
    private(set) var audioVolume: Float = 1.0
    private(set) var autoDisplaySleepInFullScreen: Bool = true
    private(set) var captureImageDirectory: String = ""
    private(set) var captureImageDirectoryBookmark: Data?
    private(set) var alwaysShowImageMenu: Bool = true
    private(set) var showVideoCaptureControls: Bool = true
    private(set) var performanceMode: String = "auto" // "auto", "high", "medium", "low"
    
    
    // MARK: - Color Correction Properties
    private(set) var brightness: Float = 0.0
    private(set) var contrast: Float = 1.0
    private(set) var hue: Float = 0.0
    
    // Color correction storage per device (keyed by device name)
    private var deviceColorCorrections: [String: (brightness: Float, contrast: Float, hue: Float)] = [:]

    // MARK: - Frame Properties
    private(set) var frameX: Float = 100
    private(set) var frameY: Float = 100
    private(set) var frameWidth: Float = 0
    private(set) var frameHeight: Float = 0

    // MARK: - Singleton
    static let shared: CPSettingsManager = CPSettingsManager()

    private init() {
        loadSettings()
    }

    // MARK: - Property Setters
    func setMirrored(_ value: Bool) {
        isMirrored = value
    }

    func setUpsideDown(_ value: Bool) {
        isUpsideDown = value
    }

    func setBorderless(_ value: Bool) {
        isBorderless = value
    }

    func setAspectRatioFixed(_ value: Bool) {
        isAspectRatioFixed = value
    }

    func setPosition(_ value: Int) {
        position = value
    }

    func setDeviceName(_ value: String) {
        deviceName = value
    }

    func setPreventDisplaySleep(_ value: Bool) {
        preventDisplaySleep = value
    }

    func setAudioInputUID(_ value: String) {
        audioInputUID = value
    }

    func setAudioOutputUID(_ value: String) {
        audioOutputUID = value
    }

    func setAudioMuted(_ value: Bool) {
        isAudioMuted = value
    }

    func setAudioVolume(_ value: Float) {
        audioVolume = max(0.0, min(1.0, value))
    }

    func setAutoDisplaySleepInFullScreen(_ value: Bool) {
        autoDisplaySleepInFullScreen = value
    }

    func setCaptureImageDirectory(_ value: String) {
        captureImageDirectory = value
    }

    func setCaptureImageDirectoryBookmark(_ value: Data?) {
        captureImageDirectoryBookmark = value
    }

    func setAlwaysShowImageMenu(_ value: Bool) {
        alwaysShowImageMenu = value
    }
    
    func setShowVideoCaptureControls(_ value: Bool) {
        showVideoCaptureControls = value
    }
    
    func setPerformanceMode(_ value: String) {
        performanceMode = value
    }
    
    func setBrightness(_ value: Float) {
        brightness = value
    }
    
    func setContrast(_ value: Float) {
        contrast = value
    }
    
    func setHue(_ value: Float) {
        hue = value
    }
    
    // MARK: - Device-Specific Color Correction
    func getColorCorrection(forDevice deviceName: String) -> (brightness: Float, contrast: Float, hue: Float) {
        if let correction = deviceColorCorrections[deviceName] {
            return correction
        }
        // Return defaults if not found
        return (brightness: 0.0, contrast: 1.0, hue: 0.0)
    }
    
    func setColorCorrection(forDevice deviceName: String, brightness: Float, contrast: Float, hue: Float) {
        deviceColorCorrections[deviceName] = (brightness: brightness, contrast: contrast, hue: hue)
        // Also update current values
        self.brightness = brightness
        self.contrast = contrast
        self.hue = hue
    }
    
    func loadColorCorrection(forDevice deviceName: String) {
        let correction = getColorCorrection(forDevice: deviceName)
        brightness = correction.brightness
        contrast = correction.contrast
        hue = correction.hue
    }

    func setFrameProperties(x: Float, y: Float, width: Float, height: Float) {
        frameX = x
        frameY = y
        frameWidth = width
        frameHeight = height
    }

    // MARK: - Settings Management
    func loadSettings() {
        logSettings(label: "before loadSettings")

        savedDeviceName = UserDefaults.standard.object(forKey: "deviceName") as? String ?? ""
        isBorderless = UserDefaults.standard.object(forKey: "borderless") as? Bool ?? false
        isMirrored = UserDefaults.standard.object(forKey: "mirrored") as? Bool ?? false
        isUpsideDown = UserDefaults.standard.object(forKey: "upsideDown") as? Bool ?? false
        isAspectRatioFixed =
            UserDefaults.standard.object(forKey: "aspectRatioFixed") as? Bool ?? false
        position = UserDefaults.standard.object(forKey: "position") as? Int ?? 0
        preventDisplaySleep =
            UserDefaults.standard.object(forKey: "preventDisplaySleep") as? Bool ?? false
        audioInputUID =
            UserDefaults.standard.object(forKey: "audioInputUID") as? String ?? ""
        audioOutputUID =
            UserDefaults.standard.object(forKey: "audioOutputUID") as? String ?? ""
        isAudioMuted = false
        audioVolume = UserDefaults.standard.object(forKey: "audioVolume") as? Float ?? 1.0
        autoDisplaySleepInFullScreen =
            UserDefaults.standard.object(forKey: "autoDisplaySleepInFullScreen") as? Bool ?? true
        captureImageDirectory =
            UserDefaults.standard.object(forKey: "captureImageDirectory") as? String ?? ""
        captureImageDirectoryBookmark =
            UserDefaults.standard.object(forKey: "captureImageDirectoryBookmark") as? Data
        alwaysShowImageMenu =
            UserDefaults.standard.object(forKey: "alwaysShowImageMenu") as? Bool ?? true
        showVideoCaptureControls =
            UserDefaults.standard.object(forKey: "showVideoCaptureControls") as? Bool ?? true
        performanceMode =
            UserDefaults.standard.object(forKey: "performanceMode") as? String ?? "auto"
        
        // Load device-specific color corrections
        if let deviceCorrectionsDict = UserDefaults.standard.dictionary(forKey: "deviceColorCorrections") as? [String: [String: Float]] {
            for (deviceName, values) in deviceCorrectionsDict {
                let brightness = values["brightness"] ?? 0.0
                let contrast = values["contrast"] ?? 1.0
                let hue = values["hue"] ?? 0.0
                deviceColorCorrections[deviceName] = (brightness: brightness, contrast: contrast, hue: hue)
            }
        }
        
        // Load default/global color correction (for backward compatibility)
        brightness = UserDefaults.standard.object(forKey: "brightness") as? Float ?? 0.0
        contrast = UserDefaults.standard.object(forKey: "contrast") as? Float ?? 1.0
        hue = UserDefaults.standard.object(forKey: "hue") as? Float ?? 0.0

        frameWidth = UserDefaults.standard.object(forKey: "frameW") as? Float ?? 0
        frameHeight = UserDefaults.standard.object(forKey: "frameH") as? Float ?? 0
        if 100 < frameWidth && 100 < frameHeight {
            frameX = UserDefaults.standard.object(forKey: "frameX") as? Float ?? 100
            frameY = UserDefaults.standard.object(forKey: "frameY") as? Float ?? 100
            NSLog("loaded : x:%f,y:%f,w:%f,h:%f", frameX, frameY, frameWidth, frameHeight)
        }

        logSettings(label: "after loadSettings")
    }

    func saveSettings() {
        logSettings(label: "saveSettings")
        UserDefaults.standard.set(deviceName, forKey: "deviceName")
        UserDefaults.standard.set(isBorderless, forKey: "borderless")
        UserDefaults.standard.set(isMirrored, forKey: "mirrored")
        UserDefaults.standard.set(isUpsideDown, forKey: "upsideDown")
        UserDefaults.standard.set(isAspectRatioFixed, forKey: "aspectRatioFixed")
        UserDefaults.standard.set(position, forKey: "position")
        UserDefaults.standard.set(preventDisplaySleep, forKey: "preventDisplaySleep")
        UserDefaults.standard.set(audioInputUID, forKey: "audioInputUID")
        UserDefaults.standard.set(audioOutputUID, forKey: "audioOutputUID")
        UserDefaults.standard.set(audioVolume, forKey: "audioVolume")
        UserDefaults.standard.set(autoDisplaySleepInFullScreen, forKey: "autoDisplaySleepInFullScreen")
        UserDefaults.standard.set(captureImageDirectory, forKey: "captureImageDirectory")
        if let bookmark = captureImageDirectoryBookmark {
            UserDefaults.standard.set(bookmark, forKey: "captureImageDirectoryBookmark")
        } else {
            UserDefaults.standard.removeObject(forKey: "captureImageDirectoryBookmark")
        }
        UserDefaults.standard.set(alwaysShowImageMenu, forKey: "alwaysShowImageMenu")
        UserDefaults.standard.set(showVideoCaptureControls, forKey: "showVideoCaptureControls")
        UserDefaults.standard.set(performanceMode, forKey: "performanceMode")
        
        // Save device-specific color corrections
        var deviceCorrectionsDict: [String: [String: Float]] = [:]
        for (deviceName, correction) in deviceColorCorrections {
            deviceCorrectionsDict[deviceName] = [
                "brightness": correction.brightness,
                "contrast": correction.contrast,
                "hue": correction.hue
            ]
        }
        UserDefaults.standard.set(deviceCorrectionsDict, forKey: "deviceColorCorrections")
        
        // Save current values for backward compatibility
        UserDefaults.standard.set(brightness, forKey: "brightness")
        UserDefaults.standard.set(contrast, forKey: "contrast")
        UserDefaults.standard.set(hue, forKey: "hue")
        UserDefaults.standard.set(frameX, forKey: "frameX")
        UserDefaults.standard.set(frameY, forKey: "frameY")
        UserDefaults.standard.set(frameWidth, forKey: "frameW")
        UserDefaults.standard.set(frameHeight, forKey: "frameH")
    }

    func clearSettings() {
        if let appDomain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: appDomain)
        }
        loadSettings()  // Reset to defaults
    }

    func logSettings(label: String) {
        NSLog(
            "%@ : %@,%@,%@borderless,%@mirrored,%@upsideDown,%@aspectRetioFixed,position:%d,%@preventDisplaySleep,audioIn:%@,audioOut:%@,%@audioMuted,volume:%.2f",
            label, deviceName, savedDeviceName,
            isBorderless ? "+" : "-",
            isMirrored ? "+" : "-",
            isUpsideDown ? "+" : "-",
            isAspectRatioFixed ? "+" : "-",
            position,
            preventDisplaySleep ? "+" : "-",
            audioInputUID,
            audioOutputUID,
            isAudioMuted ? "+" : "-",
            audioVolume)
    }
}
