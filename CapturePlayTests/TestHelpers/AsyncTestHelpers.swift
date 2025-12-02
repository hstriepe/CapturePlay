// Copyright H. Striepe ©2025
// Async testing helpers for XCTest

import XCTest

/// Helper extensions and utilities for testing async operations in XCTest
extension XCTestCase {
    
    /// Wait for an async operation with a timeout and optional condition check
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to wait (default: 5.0 seconds)
    ///   - condition: Optional condition closure to check before timing out
    ///   - description: Description for the expectation
    ///   - file: File name for assertion failures (automatically filled)
    ///   - line: Line number for assertion failures (automatically filled)
    func waitForCondition(
        timeout: TimeInterval = 5.0,
        condition: @escaping () -> Bool,
        description: String = "Condition met",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let expectation = XCTestExpectation(description: description)
        
        let startTime = Date()
        let checkInterval: TimeInterval = 0.1
        
        Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { timer in
            if condition() {
                expectation.fulfill()
                timer.invalidate()
            } else if Date().timeIntervalSince(startTime) >= timeout {
                XCTFail("Condition not met within timeout: \(description)", file: file, line: line)
                timer.invalidate()
            }
        }
        
        wait(for: [expectation], timeout: timeout)
    }
    
    /// Wait for an async operation that sets a boolean flag
    ///
    /// - Parameters:
    ///   - flag: A closure that returns the current value of the flag
    ///   - timeout: Maximum time to wait (default: 5.0 seconds)
    ///   - description: Description for the expectation
    ///
    /// Example:
    /// ```swift
    /// var completionFlag = false
    /// asyncOperation { completionFlag = true }
    /// waitForFlag({ completionFlag }, description: "Operation completed")
    /// ```
    func waitForFlag(
        _ flag: @escaping () -> Bool,
        timeout: TimeInterval = 5.0,
        description: String = "Flag set"
    ) {
        waitForCondition(timeout: timeout, condition: flag, description: description)
    }
    
    /// Execute an async closure and wait for it to complete
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to wait (default: 5.0 seconds)
    ///   - asyncOperation: The async operation to execute (should set completion flag)
    ///   - description: Description for the expectation
    func waitForAsyncOperation(
        timeout: TimeInterval = 5.0,
        description: String = "Async operation completed",
        asyncOperation: @escaping (@escaping () -> Void) -> Void
    ) {
        let expectation = XCTestExpectation(description: description)
        
        asyncOperation {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: timeout)
    }
    
    /// Assert that an async operation completes within a timeout
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to wait (default: 5.0 seconds)
    ///   - operation: The async operation to execute
    ///   - completion: Completion handler that receives the result
    func assertAsyncCompletes<T>(
        timeout: TimeInterval = 5.0,
        operation: @escaping (@escaping (T) -> Void) -> Void,
        completion: @escaping (T) -> Void
    ) {
        let expectation = XCTestExpectation(description: "Async operation completed")
        var receivedResult: T?
        
        operation { result in
            receivedResult = result
            completion(result)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: timeout)
        XCTAssertNotNil(receivedResult, "Async operation should have returned a result")
    }
}

/// Helper for testing delegate callbacks
class DelegateExpectation<T> {
    private(set) var wasCalled = false
    private(set) var receivedValue: T?
    private let expectation: XCTestExpectation
    
    init(testCase: XCTestCase, description: String = "Delegate callback") {
        expectation = XCTestExpectation(description: description)
    }
    
    func fulfill(with value: T) {
        wasCalled = true
        receivedValue = value
        expectation.fulfill()
    }
    
    func wait(timeout: TimeInterval = 5.0) {
        XCTestCase().wait(for: [expectation], timeout: timeout)
    }
}

