#!/bin/bash
# Run CapturePlay tests from command line
# Usage: ./run_tests.sh [test_class] [test_method]

set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Default destination
DESTINATION='platform=macOS'

# Build the xcodebuild command
CMD="xcodebuild test -scheme CapturePlay -destination '$DESTINATION'"

# If test class is provided, add -only-testing flag
if [ -n "$1" ]; then
    if [ -n "$2" ]; then
        # Both test class and method provided
        CMD="$CMD -only-testing:CapturePlayTests/$1/$2"
        echo "Running specific test: $1.$2"
    else
        # Only test class provided
        CMD="$CMD -only-testing:CapturePlayTests/$1"
        echo "Running all tests in class: $1"
    fi
else
    echo "Running all tests..."
fi

# Run the tests
echo ""
echo "Executing: $CMD"
echo ""
eval $CMD

echo ""
echo "✅ Tests completed! Check Xcode's Report Navigator (Cmd+9) for detailed results."

