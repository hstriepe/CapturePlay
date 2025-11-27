// Copyright H. Striepe ©2025

import Cocoa
import UserNotifications

// MARK: - CPNotificationManagerDelegate Protocol
protocol CPNotificationManagerDelegate: AnyObject {
    func notificationManager(_ manager: CPNotificationManager, didRequestPermissions granted: Bool, error: Error?)
    func notificationManager(_ manager: CPNotificationManager, didSendNotification title: String, body: String, error: Error?)
}

// MARK: - CPNotificationManager Class
class CPNotificationManager: NSObject {
    
    // MARK: - Properties
    weak var delegate: CPNotificationManagerDelegate?
    
    // MARK: - Initialization
    override init() {
        super.init()
        // Set delegate for UNUserNotificationCenter
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Permission Management
    func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    NSLog("Failed to request notification permissions: %@", error.localizedDescription)
                } else if granted {
                    NSLog("Notification permissions granted")
                } else {
                    NSLog("Notification permissions denied")
                }
                self.delegate?.notificationManager(self, didRequestPermissions: granted, error: error)
            }
        }
    }
    
    // MARK: - Sending Notifications
    func sendNotification(title: String, body: String, sound: Bool = true) {
        let center = UNUserNotificationCenter.current()
        
        // Check authorization status first
        center.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .authorized else {
                NSLog("Notification authorization status: %d (not authorized)", settings.authorizationStatus.rawValue)
                return
            }
            
            DispatchQueue.main.async {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                // Check user setting - if notification sounds are disabled, override the sound parameter
                let shouldPlaySound = sound && CPSettingsManager.shared.enableNotificationSounds
                if shouldPlaySound {
                    content.sound = .default
                }
                
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil // Deliver immediately
                )
                
                center.add(request) { error in
                    guard let self = self else { return }
                    if let error = error {
                        NSLog("Failed to send notification: %@", error.localizedDescription)
                    } else {
                        NSLog("Notification sent successfully: %@ - %@", title, body)
                    }
                    self.delegate?.notificationManager(self, didSendNotification: title, body: body, error: error)
                }
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension CPNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        // Respect the notification sounds setting
        let enableSound = CPSettingsManager.shared.enableNotificationSounds
        if #available(macOS 11.0, *) {
            var options: UNNotificationPresentationOptions = [.banner, .badge]
            if enableSound {
                options.insert(.sound)
            }
            completionHandler(options)
        } else {
            var options: UNNotificationPresentationOptions = [.alert, .badge]
            if enableSound {
                options.insert(.sound)
            }
            completionHandler(options)
        }
    }
}
