# CapturePlay

CapturePlay an app geared for using a capture device like the USB Camlink 4K to display video from consoles like a PS5, or Switch in a dock. It will display video and play audio, and is able to capture images during play. It can also capture video and audio in MOV file format.

It includes code from the [Quick Camera app on Github](https://github.com/simonguest/quick-camera) created by Simon Guest

Key eatures:

- Audio routing from any input to any output.
  - Mute and volume controls.
- Image and video capture through shortcut keys.
  - Directory can be changed in Settings.

- Notifications for key events.
- Ability to disable Display Sleep.
- Full screen disables Display Sleep and hides the cursor.
- User Settings are retained.

Capture Play can be built using XCode. Download XCode from https://developer.apple.com/xcode/ and open the Quick Camera.xcodeproj file.

In addition, with XCode or the XCode Command Line Tools installed, Quick Camera can also be built using the command line:

```bash
xcodebuild -scheme CapturePlay -configuration Release clean build
```

Your project build settings will determine the app location. I use Archive and the organizer for distribution and notarization.

### Original Quick Camera by Simon Guest

[Github quick-camera](https://github.com/simonguest/quick-camera)

Quick Camera is a macOS utility to display the output from any USB-based camera on your desktop. Quick Camera is often used for presentations where you need to show the output from an external device to your audience. 

Quick Camera supports mirroring (normal and reversed, both vertical and horizontal), can be rotated, resized to any size, and the window can be placed in the foreground.

You can find the app on the Mac App Store: https://itunes.apple.com/us/app/qcamera/id598853070?mt=12

License: Appache V2.0

