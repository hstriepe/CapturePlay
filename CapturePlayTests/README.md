# CapturePlay Test Suite

Note: These do not work reliably from within the XCode GUI. Use run_tests.sh from the command line.
This directory contains the test suite for CapturePlay, organized according to the testing strategy outlined in `TESTING_STRATEGY.md`.

## Directory Structure

```
CapturePlayTests/
├── Unit/                    # Unit tests for individual components
│   ├── Settings/           # CPSettingsManager tests
│   ├── Capture/            # CPCaptureManager tests
│   ├── Audio/              # CPAudioManager tests
│   ├── Window/             # CPWindowManager tests
│   ├── File/               # CPCaptureFileManager tests
│   ├── Notification/       # CPNotificationManager tests
│   └── Display/            # CPDisplaySleepManager tests
├── Integration/            # Integration tests for component interactions
├── Mocks/                  # Mock objects for testing
└── TestHelpers/            # Test utilities and helpers
```

## Running Tests

### In Xcode

1. Open `CapturePlay.xcodeproj` in Xcode
2. Select the `CapturePlayTests` scheme
3. Press `Cmd+U` to run all tests, or click the diamond icon next to individual tests

### Command Line

```bash
# Run all tests
xcodebuild test -project CapturePlay.xcodeproj -scheme CapturePlay

# Run specific test class
xcodebuild test -project CapturePlay.xcodeproj -scheme CapturePlay -only-testing:CapturePlayTests/CPSettingsManagerTests
```

## Test Coverage

Current test coverage is tracked in the TESTING_STRATEGY.md document. As tests are added, update the strategy document with progress.

## Adding New Tests

1. Create test files in the appropriate directory (Unit/ComponentName/)
2. Follow the naming convention: `ComponentNameTests.swift`
3. Use the Arrange-Act-Assert pattern
4. Mock external dependencies (see Mocks/ directory)
5. Ensure tests are isolated (clean up in tearDown)

## Mock Objects

Mock objects are in the `Mocks/` directory. When creating new mocks:

1. Use protocols when possible for better testability
2. Document mock behavior clearly
3. Support verification of interactions (call counts, parameters)

## Test Helpers

Common test utilities are in `TestHelpers/`:

- **AsyncTestHelpers.swift**: Utilities for testing async operations
- **TestFixtures.swift**: Factory methods for test data (when created)
- **TestUtilities.swift**: General test utilities (when created)

## Notes

- Tests should be fast and isolated
- Avoid tests that depend on hardware (cameras, audio devices)
- Use mocks for external dependencies (UserDefaults, FileManager, etc.)
- Clean up resources in tearDown methods

