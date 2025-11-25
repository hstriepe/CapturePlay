// Copyright H. Striepe ©2025

import Cocoa
import IOKit.pwr_mgt

// MARK: - CPDisplaySleepManagerDelegate Protocol
protocol CPDisplaySleepManagerDelegate: AnyObject {
    func displaySleepManager(_ manager: CPDisplaySleepManager, didChangeState isPreventing: Bool)
    func displaySleepManager(_ manager: CPDisplaySleepManager, needsNotification title: String, body: String, sound: Bool)
    func displaySleepManager(_ manager: CPDisplaySleepManager, needsErrorDisplay message: String)
    func displaySleepManager(_ manager: CPDisplaySleepManager, needsMenuItemUpdate isPreventing: Bool)
    func displaySleepManager(_ manager: CPDisplaySleepManager, needsMenuItemEnabled enabled: Bool)
}

// MARK: - CPDisplaySleepManager Class
class CPDisplaySleepManager {
    
    // MARK: - Properties
    weak var delegate: CPDisplaySleepManagerDelegate?
    
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private(set) var isPreventingDisplaySleep: Bool = false {
        didSet {
            delegate?.displaySleepManager(self, didChangeState: isPreventingDisplaySleep)
            delegate?.displaySleepManager(self, needsMenuItemUpdate: isPreventingDisplaySleep)
        }
    }
    private var displaySleepStateBeforeFullScreen: Bool?
    
    // Full screen state tracking (set by window manager)
    var isFullScreenActive: Bool = false {
        didSet {
            if !isFullScreenActive && oldValue {
                // Just exited full screen
                displaySleepStateBeforeFullScreen = nil
            }
        }
    }
    
    // MARK: - Initialization
    init() {
    }
    
    // MARK: - Display Sleep Prevention
    private func persistPreventDisplaySleepIfNeeded(_ value: Bool, persist: Bool) {
        guard persist else { return }
        CPSettingsManager.shared.setPreventDisplaySleep(value)
        CPSettingsManager.shared.saveSettings()
    }
    
    func setDisplaySleepPrevention(
        enabled: Bool,
        persist: Bool,
        notifyOnFailure: Bool
    ) {
        if enabled {
            if isPreventingDisplaySleep {
                persistPreventDisplaySleepIfNeeded(true, persist: persist)
                // Ensure menu item state is updated even if already preventing
                delegate?.displaySleepManager(self, needsMenuItemUpdate: true)
                return
            }
            
            var assertionID: IOPMAssertionID = 0
            let reason = "CapturePlay Prevent Display Sleep" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )
            
            if result == kIOReturnSuccess {
                displaySleepAssertionID = assertionID
                isPreventingDisplaySleep = true
                persistPreventDisplaySleepIfNeeded(true, persist: persist)
                delegate?.displaySleepManager(self, needsNotification: "Display Sleep", body: "Display sleep prevention enabled", sound: false)
                return
            }
            
            NSLog("Failed to create display sleep assertion: \(result)")
            if notifyOnFailure {
                delegate?.displaySleepManager(self, needsErrorDisplay: "Unable to prevent the display from sleeping. Please try again.")
            }
            return
        }
        
        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
        let wasPreventing = isPreventingDisplaySleep
        isPreventingDisplaySleep = false
        persistPreventDisplaySleepIfNeeded(false, persist: persist)
        if wasPreventing {
            delegate?.displaySleepManager(self, needsNotification: "Display Sleep", body: "Display sleep prevention disabled", sound: false)
        }
        if wasPreventing && notifyOnFailure {
            NSLog("Display sleep prevention disabled")
        }
    }
    
    func applyDisplaySleepPreferenceFromSettings(force: Bool = false) {
        if isFullScreenActive && !force { return }
        let shouldPrevent = CPSettingsManager.shared.preventDisplaySleep
        setDisplaySleepPrevention(
            enabled: shouldPrevent,
            persist: false,
            notifyOnFailure: false
        )
        // Always update menu item state to ensure it reflects current state
        delegate?.displaySleepManager(self, needsMenuItemUpdate: isPreventingDisplaySleep)
    }
    
    func toggleDisplaySleep() {
        setDisplaySleepPrevention(
            enabled: !isPreventingDisplaySleep,
            persist: true,
            notifyOnFailure: true
        )
    }
    
    // MARK: - Full Screen Integration
    func handleWillEnterFullScreen() {
        if !isFullScreenActive {
            displaySleepStateBeforeFullScreen = isPreventingDisplaySleep
        }
        delegate?.displaySleepManager(self, needsMenuItemEnabled: false)
        if CPSettingsManager.shared.autoDisplaySleepInFullScreen {
            setDisplaySleepPrevention(
                enabled: true,
                persist: false,
                notifyOnFailure: false
            )
        }
    }
    
    func handleWillExitFullScreen() {
        let previous = displaySleepStateBeforeFullScreen ?? CPSettingsManager.shared.preventDisplaySleep
        setDisplaySleepPrevention(
            enabled: previous,
            persist: true,
            notifyOnFailure: false
        )
    }
    
    func handleDidExitFullScreen() {
        displaySleepStateBeforeFullScreen = nil
        delegate?.displaySleepManager(self, needsMenuItemEnabled: true)
        applyDisplaySleepPreferenceFromSettings(force: true)
    }
    
    // MARK: - Cleanup
    func cleanup() {
        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
        isPreventingDisplaySleep = false
    }
    
    deinit {
        cleanup()
    }
}

