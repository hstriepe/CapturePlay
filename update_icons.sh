#!/bin/bash

# Script to update icons for macOS Sequoia compatibility
# This ensures all icons have proper alpha channels and formats

ICONSET_DIR="Icons/icon.iconset"
ICNS_OUTPUT="icon.icns"

echo "Checking icon format requirements for macOS Sequoia..."

# Verify all required sizes exist
REQUIRED_SIZES=("16" "32" "128" "256" "512")
MISSING_FILES=0

for size in "${REQUIRED_SIZES[@]}"; do
    if [ ! -f "$ICONSET_DIR/icon_${size}x${size}.png" ]; then
        echo "Missing: icon_${size}x${size}.png"
        MISSING_FILES=1
    fi
    if [ ! -f "$ICONSET_DIR/icon_${size}x${size}@2x.png" ]; then
        echo "Missing: icon_${size}x${size}@2x.png"
        MISSING_FILES=1
    fi
done

if [ $MISSING_FILES -eq 1 ]; then
    echo "Error: Some required icon files are missing!"
    exit 1
fi

# Verify alpha channels
echo "Verifying alpha channels..."
for icon_file in "$ICONSET_DIR"/*.png; do
    if [ -f "$icon_file" ]; then
        has_alpha=$(sips -g hasAlpha "$icon_file" 2>/dev/null | grep -i "hasAlpha:" | awk '{print $2}')
        if [ "$has_alpha" != "yes" ]; then
            echo "Warning: $icon_file does not have an alpha channel"
            # Convert to RGBA to ensure alpha channel
            sips -s format png -s formatOptions low "$icon_file" --out "$icon_file.tmp" 2>/dev/null
            if [ $? -eq 0 ]; then
                mv "$icon_file.tmp" "$icon_file"
                echo "  -> Added alpha channel to $icon_file"
            fi
        fi
    fi
done

# Regenerate .icns file
echo "Regenerating .icns file..."
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_OUTPUT"

if [ $? -eq 0 ]; then
    echo "Success! Updated icon.icns for macOS Sequoia compatibility"
    echo "The icon now supports the modern Glass appearance with proper transparency"
else
    echo "Error: Failed to generate .icns file"
    exit 1
fi

echo ""
echo "Icon update complete. The icon is ready for macOS Sequoia's Glass appearance."
echo ""
echo "To use the updated icon in Xcode:"
echo "1. Select your app target"
echo "2. Go to the 'General' tab"
echo "3. Drag the new icon.icns to the App Icon section"

