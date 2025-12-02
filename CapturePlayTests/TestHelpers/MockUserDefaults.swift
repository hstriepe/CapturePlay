// Copyright H. Striepe ©2025
// Mock UserDefaults for testing

import Foundation

/// Mock UserDefaults implementation for isolated testing.
/// This prevents tests from modifying the actual UserDefaults and allows for predictable test behavior.
class MockUserDefaults: UserDefaults {
    private var storage: [String: Any] = [:]
    
    override init(suiteName: String?) {
        // Initialize with our own storage instead of real UserDefaults
        super.init(suiteName: suiteName)!
    }
    
    /// Convenience initializer for creating a mock instance
    convenience init() {
        self.init(suiteName: nil)
    }
    
    override func object(forKey defaultName: String) -> Any? {
        return storage[defaultName]
    }
    
    override func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
    
    override func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
    
    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        return storage[defaultName] as? [String: Any]
    }
    
    override func bool(forKey defaultName: String) -> Bool {
        return (storage[defaultName] as? Bool) ?? false
    }
    
    override func integer(forKey defaultName: String) -> Int {
        return (storage[defaultName] as? Int) ?? 0
    }
    
    override func float(forKey defaultName: String) -> Float {
        return (storage[defaultName] as? Float) ?? 0.0
    }
    
    override func string(forKey defaultName: String) -> String? {
        return storage[defaultName] as? String
    }
    
    override func data(forKey defaultName: String) -> Data? {
        return storage[defaultName] as? Data
    }
    
    /// Clear all stored values (useful for test cleanup)
    func clearAll() {
        storage.removeAll()
    }
    
    /// Get all stored values (useful for debugging)
    var allValues: [String: Any] {
        return storage
    }
}

