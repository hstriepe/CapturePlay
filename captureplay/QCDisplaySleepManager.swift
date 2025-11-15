// Copyright H. Striepe - 2025

import Cocoa
import IOKit.pwr_mgt

// MARK: - QCDisplaySleepManagerDelegate Protocol
protocol QCDisplaySleepManagerDelegate: AnyObject {
    func displaySleepManager(_ manager: QCDisplaySleepManager, didChangeState isPreventing: Bool)
    func displaySleepManager(_ manager: QCDisplaySleepManager, needsNotification title: String, body: String, sound: Bool)
    func displaySleepManager(_ manager: QCDisplaySleepManager, needsErrorDisplay message: String)
    func displaySleepManager(_ manager: QCDisplaySleepManager, needsMenuItemUpdate isPreventing: Bool)
    func displaySleepManager(_ manager: QCDisplaySleepManager, needsMenuItemEnabled enabled: Bool)
}

// MARK: - QCDisplaySleepManager Class
class QCDisplaySleepManager {
    
    // MARK: - Properties
    weak var delegate: QCDisplaySleepManagerDelegate?
    
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
    func setDisplaySleepPrevention(
        enabled: Bool,
        persist: Bool,
        notifyOnFailure: Bool
    ) {
        if enabled {
            if isPreventingDisplaySleep {
                if persist {
                    QCSettingsManager.shared.setPreventDisplaySleep(true)
                }
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
                if persist {
                    QCSettingsManager.shared.setPreventDisplaySleep(true)
                }
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
        if persist {
            QCSettingsManager.shared.setPreventDisplaySleep(false)
        }
        if wasPreventing {
            delegate?.displaySleepManager(self, needsNotification: "Display Sleep", body: "Display sleep prevention disabled", sound: false)
        }
        if wasPreventing && notifyOnFailure {
            NSLog("Display sleep prevention disabled")
        }
    }
    
    func applyDisplaySleepPreferenceFromSettings(force: Bool = false) {
        if isFullScreenActive && !force { return }
        let shouldPrevent = QCSettingsManager.shared.preventDisplaySleep
        setDisplaySleepPrevention(
            enabled: shouldPrevent,
            persist: false,
            notifyOnFailure: false
        )
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
        if QCSettingsManager.shared.autoDisplaySleepInFullScreen {
            setDisplaySleepPrevention(
                enabled: true,
                persist: false,
                notifyOnFailure: false
            )
        }
    }
    
    func handleWillExitFullScreen() {
        let previous = displaySleepStateBeforeFullScreen ?? QCSettingsManager.shared.preventDisplaySleep
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

