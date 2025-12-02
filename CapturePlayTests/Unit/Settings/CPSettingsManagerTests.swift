// Copyright H. Striepe ©2025
// Unit tests for CPSettingsManager

import XCTest
@testable import CapturePlay

/// Unit tests for CPSettingsManager
/// 
/// These tests verify:
/// - Settings persistence and retrieval
/// - Default values
/// - Property validation (clamping, etc.)
/// - Device-specific color correction
/// 
/// Note: CPSettingsManager uses UserDefaults, but we test it in isolation
/// by ensuring UserDefaults is properly cleared between tests.
class CPSettingsManagerTests: XCTestCase {
    
    var settings: CPSettingsManager!
    
    override func setUp() {
        super.setUp()
        // Note: Since CPSettingsManager is a singleton, we need to work with it directly
        // In a real implementation, consider refactoring to allow dependency injection
        settings = CPSettingsManager.shared
        
        // Clear UserDefaults before each test to ensure isolation
        clearUserDefaults()
        
        // Reload settings to get defaults
        settings.loadSettings()
    }
    
    override func tearDown() {
        // Clean up UserDefaults after each test
        clearUserDefaults()
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func clearUserDefaults() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // Also clear common keys used by CPSettingsManager
        let keys = [
            "deviceName", "borderless", "mirrored", "upsideDown", "aspectRatioFixed",
            "position", "preventDisplaySleep", "audioInputUID", "audioOutputUID",
            "followSystemOutput", "audioVolume", "autoDisplaySleepInFullScreen",
            "captureImageDirectory", "captureImageDirectoryBookmark",
            "alwaysShowImageMenu", "showVideoCaptureControls", "performanceMode",
            "enableNotificationSounds", "brightness", "contrast", "hue",
            "frameX", "frameY", "frameW", "frameH", "deviceColorCorrections"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
    }
    
    // MARK: - Settings Persistence Tests
    
    func testSettingsManager_SaveAndLoad_BorderlessSetting() {
        // Arrange
        let expectedValue = true
        
        // Act
        settings.setBorderless(expectedValue)
        settings.saveSettings()
        
        // Clear in-memory state
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.isBorderless, expectedValue, "Borderless setting should be persisted and loaded correctly")
    }
    
    func testSettingsManager_SaveAndLoad_MirroredSetting() {
        // Arrange
        let expectedValue = true
        
        // Act
        settings.setMirrored(expectedValue)
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.isMirrored, expectedValue, "Mirrored setting should be persisted and loaded correctly")
    }
    
    func testSettingsManager_SaveAndLoad_UpsideDownSetting() {
        // Arrange
        let expectedValue = true
        
        // Act
        settings.setUpsideDown(expectedValue)
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.isUpsideDown, expectedValue, "UpsideDown setting should be persisted and loaded correctly")
    }
    
    func testSettingsManager_SaveAndLoad_AspectRatioFixedSetting() {
        // Arrange
        let expectedValue = true
        
        // Act
        settings.setAspectRatioFixed(expectedValue)
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.isAspectRatioFixed, expectedValue, "AspectRatioFixed setting should be persisted and loaded correctly")
    }
    
    func testSettingsManager_SaveAndLoad_PositionSetting() {
        // Arrange
        let expectedValue = 2
        
        // Act
        settings.setPosition(expectedValue)
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.position, expectedValue, "Position setting should be persisted and loaded correctly")
    }
    
    func testSettingsManager_SaveAndLoad_AudioInputUID() {
        // Arrange
        let expectedUID = "test-input-device-uid"
        
        // Act
        settings.setAudioInputUID(expectedUID)
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.audioInputUID, expectedUID, "Audio input UID should be persisted and loaded correctly")
    }
    
    func testSettingsManager_SaveAndLoad_AudioOutputUID() {
        // Arrange
        let expectedUID = "test-output-device-uid"
        
        // Act
        settings.setAudioOutputUID(expectedUID)
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.audioOutputUID, expectedUID, "Audio output UID should be persisted and loaded correctly")
    }
    
    func testSettingsManager_SaveAndLoad_FollowSystemOutput() {
        // Arrange
        let expectedValue = true
        
        // Act
        settings.setFollowSystemOutput(expectedValue)
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.followSystemOutput, expectedValue, "FollowSystemOutput setting should be persisted and loaded correctly")
    }
    
    func testSettingsManager_SaveAndLoad_PerformanceMode() {
        // Arrange
        let expectedMode = "high"
        
        // Act
        settings.setPerformanceMode(expectedMode)
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.performanceMode, expectedMode, "Performance mode should be persisted and loaded correctly")
    }
    
    func testSettingsManager_SaveAndLoad_EnableNotificationSounds() {
        // Arrange
        let expectedValue = true
        
        // Act
        settings.setEnableNotificationSounds(expectedValue)
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.enableNotificationSounds, expectedValue, "EnableNotificationSounds setting should be persisted and loaded correctly")
    }
    
    // MARK: - Default Values Tests
    
    func testSettingsManager_LoadDefaults_WhenNoSettingsSaved() {
        // Arrange & Act (setUp already clears and loads defaults)
        
        // Assert - Verify default values
        XCTAssertFalse(settings.isBorderless, "Default borderless should be false")
        XCTAssertFalse(settings.isMirrored, "Default mirrored should be false")
        XCTAssertFalse(settings.isUpsideDown, "Default upsideDown should be false")
        XCTAssertFalse(settings.isAspectRatioFixed, "Default aspectRatioFixed should be false")
        XCTAssertEqual(settings.position, 0, "Default position should be 0")
        XCTAssertFalse(settings.preventDisplaySleep, "Default preventDisplaySleep should be false")
        XCTAssertEqual(settings.audioInputUID, "", "Default audioInputUID should be empty")
        XCTAssertEqual(settings.audioOutputUID, "", "Default audioOutputUID should be empty")
        XCTAssertFalse(settings.followSystemOutput, "Default followSystemOutput should be false")
        XCTAssertEqual(settings.audioVolume, 1.0, "Default audioVolume should be 1.0")
        XCTAssertTrue(settings.autoDisplaySleepInFullScreen, "Default autoDisplaySleepInFullScreen should be true")
        XCTAssertEqual(settings.captureImageDirectory, "", "Default captureImageDirectory should be empty")
        XCTAssertTrue(settings.alwaysShowImageMenu, "Default alwaysShowImageMenu should be true")
        XCTAssertTrue(settings.showVideoCaptureControls, "Default showVideoCaptureControls should be true")
        XCTAssertEqual(settings.performanceMode, "auto", "Default performanceMode should be 'auto'")
        XCTAssertFalse(settings.enableNotificationSounds, "Default enableNotificationSounds should be false")
    }
    
    // MARK: - Property Validation Tests
    
    func testSettingsManager_SetAudioVolume_ClampsToMaximum() {
        // Arrange
        let volumeAboveMax: Float = 1.5
        
        // Act
        settings.setAudioVolume(volumeAboveMax)
        
        // Assert
        XCTAssertEqual(settings.audioVolume, 1.0, "Volume should be clamped to maximum of 1.0")
    }
    
    func testSettingsManager_SetAudioVolume_ClampsToMinimum() {
        // Arrange
        let volumeBelowMin: Float = -0.5
        
        // Act
        settings.setAudioVolume(volumeBelowMin)
        
        // Assert
        XCTAssertEqual(settings.audioVolume, 0.0, "Volume should be clamped to minimum of 0.0")
    }
    
    func testSettingsManager_SetAudioVolume_AcceptsValidRange() {
        // Arrange
        let validVolumes: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
        
        // Act & Assert
        for volume in validVolumes {
            settings.setAudioVolume(volume)
            XCTAssertEqual(settings.audioVolume, volume, accuracy: 0.001, "Volume \(volume) should be accepted")
        }
    }
    
    // MARK: - Color Correction Tests
    
    func testSettingsManager_SetAndGetColorCorrection_GlobalValues() {
        // Arrange
        let brightness: Float = 0.5
        let contrast: Float = 1.5
        let hue: Float = 0.3
        
        // Act
        settings.setBrightness(brightness)
        settings.setContrast(contrast)
        settings.setHue(hue)
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.brightness, brightness, accuracy: 0.001, "Brightness should be persisted")
        XCTAssertEqual(settings.contrast, contrast, accuracy: 0.001, "Contrast should be persisted")
        XCTAssertEqual(settings.hue, hue, accuracy: 0.001, "Hue should be persisted")
    }
    
    func testSettingsManager_SetAndGetColorCorrection_DeviceSpecific() {
        // Arrange
        let deviceName = "Test Device"
        let brightness: Float = 0.3
        let contrast: Float = 1.2
        let hue: Float = 0.1
        
        // Act
        settings.setColorCorrection(forDevice: deviceName, brightness: brightness, contrast: contrast, hue: hue)
        settings.saveSettings()
        settings.loadSettings()
        let correction = settings.getColorCorrection(forDevice: deviceName)
        
        // Assert
        XCTAssertEqual(correction.brightness, brightness, accuracy: 0.001, "Device-specific brightness should be stored")
        XCTAssertEqual(correction.contrast, contrast, accuracy: 0.001, "Device-specific contrast should be stored")
        XCTAssertEqual(correction.hue, hue, accuracy: 0.001, "Device-specific hue should be stored")
    }
    
    func testSettingsManager_GetColorCorrection_ReturnsDefaults_WhenDeviceNotFound() {
        // Arrange
        let nonExistentDevice = "Non-Existent Device"
        
        // Act
        let correction = settings.getColorCorrection(forDevice: nonExistentDevice)
        
        // Assert
        XCTAssertEqual(correction.brightness, 0.0, accuracy: 0.001, "Should return default brightness for unknown device")
        XCTAssertEqual(correction.contrast, 1.0, accuracy: 0.001, "Should return default contrast for unknown device")
        XCTAssertEqual(correction.hue, 0.0, accuracy: 0.001, "Should return default hue for unknown device")
    }
    
    func testSettingsManager_LoadColorCorrection_UpdatesCurrentValues() {
        // Arrange
        let deviceName = "Test Device"
        let brightness: Float = 0.4
        let contrast: Float = 1.3
        let hue: Float = 0.2
        
        // Act
        settings.setColorCorrection(forDevice: deviceName, brightness: brightness, contrast: contrast, hue: hue)
        settings.loadColorCorrection(forDevice: deviceName)
        
        // Assert
        XCTAssertEqual(settings.brightness, brightness, accuracy: 0.001, "Loading device correction should update current brightness")
        XCTAssertEqual(settings.contrast, contrast, accuracy: 0.001, "Loading device correction should update current contrast")
        XCTAssertEqual(settings.hue, hue, accuracy: 0.001, "Loading device correction should update current hue")
    }
    
    // MARK: - Frame Properties Tests
    
    func testSettingsManager_SetAndGetFrameProperties() {
        // Arrange
        let x: Float = 100.0
        let y: Float = 200.0
        let width: Float = 1920.0
        let height: Float = 1080.0
        
        // Act
        settings.setFrameProperties(x: x, y: y, width: width, height: height)
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertEqual(settings.frameX, x, accuracy: 0.001, "Frame X should be persisted")
        XCTAssertEqual(settings.frameY, y, accuracy: 0.001, "Frame Y should be persisted")
        XCTAssertEqual(settings.frameWidth, width, accuracy: 0.001, "Frame width should be persisted")
        XCTAssertEqual(settings.frameHeight, height, accuracy: 0.001, "Frame height should be persisted")
    }
    
    // MARK: - Settings Clearing Tests
    
    func testSettingsManager_ClearSettings_ResetsToDefaults() {
        // Arrange
        settings.setBorderless(true)
        settings.setMirrored(true)
        settings.setAudioVolume(0.5)
        settings.saveSettings()
        
        // Act
        settings.clearSettings()
        
        // Assert
        XCTAssertFalse(settings.isBorderless, "Borderless should be reset to default after clear")
        XCTAssertFalse(settings.isMirrored, "Mirrored should be reset to default after clear")
        XCTAssertEqual(settings.audioVolume, 1.0, "Audio volume should be reset to default after clear")
    }
    
    // MARK: - Multiple Settings Tests
    
    func testSettingsManager_SaveAndLoad_MultipleSettings() {
        // Arrange
        settings.setBorderless(true)
        settings.setMirrored(true)
        settings.setUpsideDown(true)
        settings.setAspectRatioFixed(true)
        settings.setPosition(3)
        settings.setAudioInputUID("input-uid")
        settings.setAudioOutputUID("output-uid")
        settings.setAudioVolume(0.75)
        settings.setFollowSystemOutput(true)
        
        // Act
        settings.saveSettings()
        settings.loadSettings()
        
        // Assert
        XCTAssertTrue(settings.isBorderless)
        XCTAssertTrue(settings.isMirrored)
        XCTAssertTrue(settings.isUpsideDown)
        XCTAssertTrue(settings.isAspectRatioFixed)
        XCTAssertEqual(settings.position, 3)
        XCTAssertEqual(settings.audioInputUID, "input-uid")
        XCTAssertEqual(settings.audioOutputUID, "output-uid")
        XCTAssertEqual(settings.audioVolume, 0.75, accuracy: 0.001)
        XCTAssertTrue(settings.followSystemOutput)
    }
}

