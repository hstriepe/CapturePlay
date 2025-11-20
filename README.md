# CapturePlay

CapturePlay is an app designed for use with a capture device like the USB Camlink 4K to display video from consoles like a PS5 or a docked Switch. It displays video and plays audio, and can capture images during playback. It can also capture video and audio in the MOV file format.

It includes code from the [Quick Camera app on Github,](https://github.com/simonguest/quick-camera) created by Simon Guest.

Key features:

- Audio routing from any input to any output.
  - Mute and volume controls.
- Video Controls
  - Brightness, contrast, hue
  - Saved per input choice
  - Video capture button overlay

- Image and video capture through shortcut keys.
  - The directory can be changed in Settings.

- Notifications for key events.
- Ability to disable Display Sleep.
- Full screen disables Display Sleep and hides the cursor.
- User Settings are retained.

For a complete feature set, read the MANUAL, which is also included as Help in the app.

Capture Play can be built using XCode. Download XCode from https://developer.apple.com/xcode/ and open the Quick Camera.xcodeproj file.

In addition, with XCode or the XCode Command Line Tools installed, Quick Camera can also be built using the command line:

```bash
xcodebuild -scheme CapturePlay -configuration Release clean build
```

Your project build settings will determine the app location. I use Archive and the organizer for distribution and notarization.

### Original Quick Camera by Simon Guest

[Github quick-camera](https://github.com/simonguest/quick-camera)

Quick Camera is a macOS utility to display the output from any USB-based camera on your desktop. Quick Camera is often used for presentations where you need to show the output from an external device to your audience. 

Quick Camera supports mirroring (normal and reversed, both vertical and horizontal), rotation, resizing to any size, and placement in the foreground.

You can find the app on the Mac App Store: https://itunes.apple.com/us/app/qcamera/id598853070?mt=12

License: Apache V2.0

