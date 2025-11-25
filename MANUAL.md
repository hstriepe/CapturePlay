# CapturePlay User Manual

**Version 3.5**

CapturePlay is a macOS application designed to display video and audio from USB capture devices (such as the USB Camlink 4K) connected to gaming consoles, such as the PlayStation 5 or Nintendo Switch, in a dock. It also connects to Continuity Cameras on iPhone. The application provides real-time video display, audio routing, image capture, and video recording capabilities.

---

## Table of Contents

1. [Introduction](#introduction)
2. [System Requirements](#system-requirements)
3. [Getting Started](#getting-started)
4. [Menu Structure](#menu-structure)
5. [Video Features](#video-features)
6. [Audio Features](#audio-features)
7. [Capture Features](#capture-features)
8. [Settings and Preferences](#settings-and-preferences)
9. [Keyboard Shortcuts](#keyboard-shortcuts)
10. [Notifications](#notifications)
11. [Troubleshooting](#troubleshooting)

---

## Introduction

CapturePlay enables you to:

- **Display video** from USB capture devices in real-time, including MacBook cameras
- **Route audio** from capture devices to any output device
- **Capture images** during gameplay or video viewing
- **Record video** with audio in QuickTime-compatible MOV format
- **Transform video** with mirroring, rotation, and aspect ratio controls
- **Customize the window** with borderless mode and full-screen support
- **Prevent display sleep** during full-screen viewing or recording

---

## System Requirements

- **macOS**: 14.6 (Sequoia) or later to support Continuity Camera.
- **Hardware**: 
  - USB capture device (e.g., Elgato Camlink 4K, AVMedia, 4k HDMI Capture card, or generic USB capture cards)
  - MacBook or Studio Display Camera
  - iPhone Continuity Camera (requires macOS 14.6 Sequoia, or later, and iOS 16.0 or later)
- **Permissions**: 
  - Camera access (for video capture devices)
  - Microphone access (for audio capture)

---

## Getting Started

### First Launch

1. **Launch CapturePlay** from your Applications folder or Dock.
2. **Grant permissions** when macOS prompts for:
   - Camera access (required for video display)
   - Microphone access (required for audio capture)
3. **Connect your USB capture device** before or after launching the app.

### Device Detection

- CapturePlay automatically detects connected USB video capture devices on startup.
- **Continuity Camera**: iPhone Continuity Camera is supported (macOS 13.0+ required).
- If no devices are found, the app will display an error and close.
- USB devices are monitored: connecting or disconnecting a device will automatically update the device list.

### Initial Setup

1. **Select your video source**: Go to **Video > Select Source** and choose your capture device.
2. **Configure audio** (optional):
   - Choose an audio input: **Audio > Select Source**
   - Choose an audio output: **Audio > Select Output**
3. **Set capture directory**: Go to **CapturePlay > Settings** and set where captured images and videos should be saved.

---

## Menu Structure

### CapturePlay Menu (Application Menu)

- **About CapturePlay**: Displays version information and copyright
- **Settings…** (⌘,): Opens the CapturePlay Settings dialog
- **Hide CapturePlay** (⌘H): Hides the application window
- **Hide Others** (⌥⌘H): Hides all other applications
- **Show All**: Shows all hidden applications
- **Quit CapturePlay** (⌘Q): Exits the application

**Note**: Window position, size, and most other settings are automatically saved when you close the application.

### File Menu

- **Open Capture Folder** (⌘O): Opens the folder where captured images and videos are saved in Finder
- **Save Image…** (⌘⇧S): Saves the current video frame to a location of your choice
- **Capture Image** (⌘S): Captures an image and saves it to the capture directory with an automatic filename
- **Capture Video** (⌘V): Starts or stops video recording

### Edit Menu

- **Copy** (⌘C): Copies the current window capture to the clipboard

- The rest of the menu is inactive

### Video Menu

- **Select Source**: Choose which video capture device to use (submenu lists all available devices)
- **Image**: Image transformation options - use the Option key to show the Menu item unless it is set to always show in Settings.
  - **Mirror**:
    - **Mirror Horizontally** (⌘M): Flips the video horizontally (left-right)
    - **Mirror Vertically** (⌘⇧H): Flips the video vertically (top-bottom)
  - **Rotate**:
    - **Rotate Left** (⌘L): Rotates video 90° counter-clockwise
    - **Rotate Right** (⌘R): Rotates video 90° clockwise
- **Borderless Mode** (⌘B): Toggles window border on/off
- **Fix Aspect Ratio** (⌘A): Locks/unlocks the window aspect ratio to match video
- **Fit to Actual Size** (⌃⌘A): Resizes window to match the video's native resolution
- **Color Correction…**: Opens the Color Correction dialog for adjusting brightness, contrast, and hue
- **Enter Full Screen** (⌃⌘F): Enters full-screen mode
- **Display Sleep Prevention** (⌘D): Toggles display sleep prevention on/off

### Audio Menu

- **Select Source**: Choose audio input device (submenu lists all available audio capture devices)
- **Select Output**: Choose audio output device (submenu lists all available audio output devices)
- **Mute** (⌘M): Toggles audio muting on/off
- **Volume**: Adjust audio volume using the slider (submenu item)

### Window Menu

- **Minimize**: Minimizes the window to the Dock
- **Zoom**: Maximizes the window
- **Bring All to Front**: Brings all CapturePlay windows to the front

### Help Menu

- **CapturePlay Help** (⌘?): Opens the help system (if available)

---

## Video Features

### Selecting a Video Source

1. Connect your USB capture device or enable iPhone Continuity Camera.
2. Go to **Video > Select Source**.
3. Choose your device from the list.
4. The video feed will start automatically.

**Note**: CapturePlay monitors USB connections. If you connect or disconnect a device, the device list will update automatically.

#### Using iPhone Continuity Camera

CapturePlay supports iPhone Continuity Camera, which lets you use your iPhone as a video input device over Wi-Fi or USB.

**Requirements**:

- **macOS**: 14.6 (Sequoia) or later
- **iOS**: 16.0 or later on iPhone
- **Same Apple ID**: Both devices must be signed in to the same Apple ID with two-factor authentication enabled
- **Handoff enabled**: On iPhone: Settings > General > AirPlay & Handoff > Enable "Handoff" and "Continuity Camera"
- **Network**: Both devices must be on the same Wi-Fi network, with Wi-Fi and Bluetooth enabled on both
- **Positioning**: iPhone should be locked, stable, and positioned with the rear cameras facing you in landscape orientation

**Setup**:
1. Ensure both devices meet the requirements above.
2. Position your iPhone as described.
3. Your iPhone will appear in **Video > Select Source** as "iPhone" or "Continuity Camera".
4. Select it from the device list.
5. The video feed will start automatically.

**Troubleshooting Continuity Camera**:
- Ensure Handoff is enabled on both devices
- Check that both devices are on the same Wi-Fi network
- Disable VPNs on both devices (VPNs can interfere with Continuity Camera)
- Disable AirPlay Receiver on your Mac: System Settings > General > AirDrop & Handoff > Turn off "AirPlay Receiver"
- Restart both devices if connection issues persist

### Image Transformations

Image transformation options (Mirror and Rotate) are accessed through **Video > Image**.

### Mirroring

Mirroring flips the video display:

- **Mirror Horizontally** (⌘M): Flips left and right (useful for webcam-style "mirror mode")
- **Mirror Vertically** (⌘⇧H): Flips top and bottom (useful for upside-down cameras)

Both mirroring options can be combined. The mirroring state is saved in preferences.

**Note**: If you prefer to keep the Image menu hidden until needed, you can hold Option (⌥) when opening Video > Image. At the same time, the "Always show the Image submenu under Video" setting is off.

### Rotation

Rotate the video to match your camera orientation:

- **Rotate Left** (⌘L): 90° counter-clockwise
- **Rotate Right** (⌘R): 90° clockwise

Rotation position is saved in preferences and applied automatically on startup.

**Note**: If you prefer to keep the Image menu hidden until needed, you can hold Option (⌥) when opening Video > Image while the "Always show the Image submenu under Video" setting is off.

### Color Correction

**Color Correction…** (Video menu) opens a non-modal dialog for adjusting video color:

- **Brightness**: Adjust from -1.0 (darker) to 1.0 (brighter)
- **Contrast**: Adjust from 0.0 (low) to 2.0 (high), default is 1.0
- **Hue**: Adjust from -180° to +180°
- **Reset**: Restores all values to defaults (Brightness: 0.0, Contrast: 1.0, Hue: 0.0°)
- **Close**: Closes the dialog (settings are saved automatically)

**Device-Specific Settings**: Color correction settings are saved per video device by name. Each device (USB capture card, Continuity Camera, etc.) maintains its own brightness, contrast, and hue values. When you switch devices, the saved color correction settings for that device are automatically loaded and applied.

The dialog can remain open while using the application and can be moved independently.

### Borderless Mode

**Borderless Mode** (⌘B) removes the window title bar and borders:

- **Enabled**: Window has no border, is always on top, and is movable by dragging anywhere
- **Disabled**: Standard macOS window with title bar

**Note**: Borderless mode is automatically disabled when entering full-screen mode.

### Aspect Ratio Control

- **Fix Aspect Ratio** (⌘A): When enabled, the window maintains the video's aspect ratio when resizing
- **Fit to Actual Size** (⌃⌘A): Resizes the window to match the video's native resolution

### Full Screen Mode

**Enter Full Screen** (⌃⌘F) or click the green traffic light button:

- Video fills the entire screen
- The cursor is automatically hidden
- Display sleep prevention is automatically enabled (if configured in preferences)
- Press Escape to exit

**Note**: Some features (like "Save Image") are not available in full-screen mode.

### Display Sleep Prevention

**Display Sleep** Prevention (⌘D) prevents your Mac's display from sleeping:

- Useful during typical game play and long recording sessions
- Can be enabled/disabled manually via menu
- Automatically enabled in full-screen mode (if configured in preferences)

### Translucent Title Bar

CapturePlay features a QuickTime Player-style translucent title bar for a clean viewing experience:

- **Recording Controls Integration**: Video capture controls follow the same visibility behavior, appearing on hover and hiding when the mouse moves away (except during recording, when they remain always visible)


---

## Audio Features

### Selecting Audio Input

The audio input comes from your capture device:

1. Go to **Audio > Select Source**.
2. Choose your audio capture device from the list.
3. Audio will route to the selected output device.

**Note**: If no audio input is selected, videos will be recorded without audio.

### Selecting Audio Output

Choose where audio is played:

1. Go to **Audio > Select Output**.
2. Choose your output device (speakers, headphones, etc.).

**Note**: Audio settings are saved in preferences.

### Mute

**Mute** (⌘M in Audio menu) temporarily disables audio output without changing volume settings.

**Note**: The mute keyboard shortcut (⌘M) is shared with "Mirror Horizontally" in the Video menu. Use the menu item if there's a conflict.

### Volume Control

Adjust volume using the slider in **Audio > Volume**:

- Drag the slider to adjust output volume
- Changes apply immediately
- Volume setting is saved in preferences

---

## Capture Features

### Image Capture

Three methods for capturing images:

#### Method 1: Copy to Clipboard (⌘C)

- Copies the current window capture to the clipboard
- Available via **Edit > Copy**
- Useful for quickly pasting into other applications
- Image is copied in PNG format
- Works the same as saving, but places the image directly in the clipboard

#### Method 2: Quick Capture (⌘S)

- Captures current frame instantly
- Saves to capture directory with automatic filename
- Filename format: `CapturePlay Image YYYY-MM-DD at HH.mm.ss.png`
- Shows notification when saved

#### Method 3: Save Image (⌘⇧S)

- Opens a save dialog to choose location
- Allows you to name the file
- Useful when you want to save to a specific location

**Image Format**: PNG (highest quality)

**Note**: Image capture temporarily removes the window border (if present) to capture a clean image, then restores it. Copy to clipboard uses the same capture method.

### Video Recording

**Capture Video** (⌘V) toggles video recording:

- **Start Recording**: Creates a new video file in the capture directory
- **Stop Recording**: Finalizes the video file
- **File Format**: QuickTime MOV (compatible with macOS, Windows, and most video players)
- **Audio**: Included if an audio input is selected
- **Filename Format**: `CapturePlay Video YYYY-MM-DD at HH.mm.ss.mov`
- **Notifications**: Shows notifications when recording starts and stops
- **Cooldown Period**: After stopping recording, there is a 1-second delay before you can start recording again to prevent errors

**Video Recording Details**:

- Video resolution matches the source device's native resolution
- Frame rate matches the device's configured frame rate (typically 60fps or 59.94fps)
- Audio is encoded as AAC at 256 Kbps (QuickTime-compatible)
- Videos are saved with timestamps to avoid filename conflicts

**Recording Status**:

- The "Capture Video" menu item shows a checkmark (✓) when recording is active
- A notification appears when recording starts and stops
- Recording can be stopped by pressing ⌘V again
- An on-screen recording control button appears when recording starts (if enabled in Settings)
  - **Red Circle**: Idle state (click to start recording)
  - **Red Square**: Recording state (slowly blinks, click to stop recording)
  - The control is positioned in the bottom-right corner of the video window
  - The control is excluded from screen recordings and saved videos
  - **Visibility**: Controls follow the translucent title bar behavior - they appear when you hover over the window and disappear when the mouse moves away, except while recording when they remain always visible
  - These controls can be disabled in Settings.

**Note**: Ensure you have sufficient disk space. Video files can be large, especially at high resolutions and frame rates.

### Opening Capture Folder

**Open Capture Folder** (⌘O) opens the capture directory in Finder, where all captured images and videos are saved.

---

## Settings and Preferences

### CapturePlay Settings Dialog

Open **CapturePlay > Settings…** (⌘,)

#### Capture Image Directory

- **Default Location**: `~/Pictures/CapturePlay`
- **Browse…**: Click to select a different folder
- **Path Field**: Displays current directory path (supports tilde notation, e.g., `~/Documents`)

**Note**: If you select a folder outside your home directory, CapturePlay will request permission to access it. macOS will prompt you to grant access.

#### Display Sleep in Full Screen

- **Toggle**: "Automatically prevent display sleep during full screen"
- When enabled, display sleep prevention is automatically activated when entering full-screen mode
- When disabled, you must manually toggle display sleep prevention

#### Image Menu Visibility

- **Toggle**: "Always show the Image submenu under Video"
- When enabled, the **Video > Image** menu is always visible.
- When disabled, the Image menu can still be revealed by holding Option (⌥) while opening the Video menu.

#### Performance Mode

- **Selector**: "Performance Mode" popup menu
- Controls video quality and frame rate optimizations for different system capabilities
- **Options**:
  - **Auto** (default): Automatically detects your system's performance and applies appropriate optimizations
    - Slower systems (≤4 CPU cores or <8GB RAM): Uses Medium optimizations
    - Faster systems (>4 cores and ≥8GB RAM): Uses High quality settings
  - **High**: Maximum quality, no performance optimizations
    - Uses highest available resolution and frame rate
    - Best for modern Macs with powerful CPUs/GPUs
  - **Medium**: Balanced quality and performance
    - Limits resolution to 720p (1280×720) maximum
    - Frame rate limited to 30fps for smoother playback
    - Best for mid-range systems or when you want smoother playback
  - **Low**: Maximum performance, reduced quality
    - Limits resolution to 480p (640×480) maximum
    - Frame rate limited to 24fps for consistent playback
    - Best for older/slower systems or when prioritizing smooth playback over quality
    - Note: Some games may show poor framerates despite these optimizations on slower systems and capture devices.

**What Gets Optimized**:

- Video resolution (lower resolutions reduce processing load)
- Frame rate (limits to 24–30fps for consistent timing)
- Session preset (controls capture quality level)
- Frame smoothing (uses VSync and frame timing for smoother playback)

**Recommendations**:
- **Leave on Auto** unless you have specific needs — it automatically adapts to your system
- Use **High** if you have a powerful Mac and want maximum quality
- Use **Medium** if you experience stuttering or frame drops
- Use **Low** if you have an older Mac or need the smoothest possible playback

#### Video Capture Controls

- **Toggle**: "Show video capture controls"
- When enabled, an on-screen recording control button appears when recording starts
- When disabled, the on-screen control button is hidden
- The button appears in the bottom-right corner of the video window
- **Behavior**: The control follows the translucent title bar visibility - it appears on mouse hover and hides when the mouse moves away, except during recording, when it remains always visible
- Click the button to start or stop recording

#### Saving Settings

- Click **OK** to save changes
- Click **Cancel** to discard changes
- Preferences are saved immediately when you click OK

### Automatic Settings Retention

CapturePlay automatically saves and restores your settings:

- **Window position and size**: Automatically saved when you close the application
- **Video settings**: Rotation, mirroring, borderless mode, and aspect ratio preferences
- **Audio settings**: Input/output device selections and volume
- **Color correction settings**: Brightness, contrast, and hue values (saved per device by name)
- **Settings**: Capture directory, display sleep preferences, Image menu visibility, video capture controls visibility, and performance mode

All settings are automatically loaded when you launch CapturePlay.

### Automatic Settings Management

All settings are automatically saved when you close the application and automatically loaded when you launch CapturePlay. There is no manual "Save Settings" or "Clear Settings" option — settings are managed automatically.

---

## Keyboard Shortcuts

### Global Shortcuts

| Shortcut | Action | Menu Location |
|----------|--------|---------------|
| ⌘, | Settings | CapturePlay > Settings… |
| ⌘H | Hide App | CapturePlay > Hide CapturePlay |
| ⌥⌘H | Hide Others | CapturePlay > Hide Others |
| ⌘Q | Quit | CapturePlay > Quit CapturePlay |
| ⌘O | Open Capture Folder | File > Open Capture Folder |
| ⌘C | Copy Window | Edit > Copy |
| ⌘⇧S | Save Image | File > Save Image… |
| ⌘S | Capture Image | File > Capture Image |
| ⌘V | Capture Video | File > Capture Video |
| ⌘M | Mirror Horizontally | Video > Image > Mirror > Mirror Horizontally |
| ⌘⇧H | Mirror Vertically | Video > Image > Mirror > Mirror Vertically |
| ⌘L | Rotate Left | Video > Image > Rotate > Rotate Left |
| ⌘R | Rotate Right | Video > Image > Rotate > Rotate Right |
| ⌘B | Borderless Mode | Video > Borderless Mode |
| ⌘A | Fix Aspect Ratio | Video > Fix Aspect Ratio |
| ⌃⌘A | Fit to Actual Size | Video > Fit to Actual Size |
| ⌃⌘F/FnF | Enter Full Screen | Video > Enter Full Screen |
| ⌘D | Display Sleep Prevention | Video > Display Sleep |

### Menu-Specific Shortcuts

- **Audio > Mute** (⌘M): Shares shortcut with "Mirror Horizontally" — use the menu item directly if there's a conflict

---

## Notifications

CapturePlay can send notifications for key events:

- **Image Captured**: When an image is saved to the capture directory
- **Video Recording Started**: When video recording begins
- **Video Recording Stopped**: When video recording ends and the file is saved
- **Display Sleep Prevention**: When display sleep prevention is enabled or disabled

### Notification Permissions

On first launch, macOS will ask for notification permissions. Grant permission to receive notifications about captures and recordings.

**To enable/disable notifications later**:

1. Open **System Preferences > Notifications & Focus**
2. Find "CapturePlay" in the list
3. Adjust notification settings as desired

---

## Troubleshooting

### No Video Display

**Problem**: Video window is black or shows no image.

**Solutions**:

1. **Check device connection**: Ensure your USB capture device is connected. Use System Information > USB to see whether the device is showing up
2. **Select correct source**: Go to **Video > Select Source** and verify the correct device is selected
3. **Check device permissions**: Ensure CapturePlay has camera access (System Preferences > Security & Privacy > Privacy > Camera)
4. **Try a different USB port**: Some USB ports may not provide sufficient power
5. **Restart CapturePlay**: Quit and relaunch the application
6. **Check device compatibility**: Ensure your capture device is recognized by macOS (check System Information > USB)

### No Audio

**Problem**: No audio is heard during playback or recording.

**Solutions**:

1. **Select audio input**: Go to **Audio > Select Source** and choose an audio device
2. **Select audio output**: Go to **Audio > Select Output** and choose speakers or headphones
3. **Check mute status**: Ensure audio is not muted (Audio > Mute should be unchecked)
4. **Check volume**: Adjust volume in **Audio > Volume**
5. **Check microphone permissions**: Ensure CapturePlay has microphone access (System Preferences > Security & Privacy > Privacy > Microphone)
6. **Verify audio source**: Some capture devices have separate audio inputs — ensure audio is connected to the correct input

### Audio Stops Working After Changing Video Source

**Problem**: Audio works initially, but stops after switching video devices.

**Solution**: This is a known behavior when switching devices. The audio manager should automatically reconnect. If it doesn't:

1. Go to **Audio > Select Source** and re-select your audio input
2. Restart CapturePlay if the issue persists

### Image Capture Not Working

**Problem**: Image capture fails or shows an error.

**Solutions**:

1. Check capture directory**: Ensure the capture directory exists and is writable (Preferences > Browse…)
3. **Check disk space**: Ensure you have sufficient free disk space
4. **Check permissions**: If using a custom directory, grant CapturePlay permission to access it. Use the Browse button to select your desired directory, and macOS will prompt for permissions if they are required

### Video Recording Not Working

**Problem**: Video recording doesn't start or fails.

**Solutions**:

1. **Check capture directory**: Ensure the capture directory exists and is writable
2. **Check disk space**: Video files can be large — ensure sufficient free space
3. **Check permissions**: Ensure CapturePlay can write to the capture directory
4. **Verify device supports recording**: Some devices may have limitations
5. **Try stopping and restarting**: Use ⌘V to stop, then start again (note: there is a 1-second cooldown after stopping)

### Window Won't Resize or Position Correctly

**Problem**: Window size or position is not as expected.

**Solutions**:

1. **Reset window**: Quit and relaunch the app to reset window state, or manually resize/reposition the window
2. **Disable aspect ratio lock**: Uncheck **Video > Fix Aspect Ratio**
3. **Fit to actual size**: Use **Video > Fit to Actual Size** (⌃⌘A) to match video resolution

### Display Sleep Still Occurs

**Problem**: Display sleeps despite enabling prevention.

**Solutions**:

1. **Check menu state**: Ensure **Video > Display Sleep** shows a checkmark (✓)
2. **Check System Preferences**: macOS power settings may override app settings
3. **Try toggling**: Disable and re-enable display sleep prevention
4. **Full-screen mode**: Display sleep prevention works more reliably in full-screen mode

### Preferences Not Saving

**Problem**: Settings don't persist between launches.

**Solutions**:

1. **Check permissions**: Ensure CapturePlay can write to the preferences location (usually `~/Library/Preferences/`)
2. **Reset preferences**: Quit the app, delete the preferences file at `~/Library/Preferences/org.windholm.captureplay.plist`, then relaunch and reconfigure
3. **Restart the application**: Settings are automatically saved when you close the app — ensure you close it normally (not force quit)

### Device Not Detected

**Problem**: USB capture device or Continuity Camera is not listed in "Select Source".

**Solutions**:

1. Check whether the USB device exists in System Information. You can open that quickly by pressing the Option key while selecting the Apple Menu
2. **Check USB connection**: Unplug and reconnect the device (for USB devices)
3. **Try different USB port**: Use a USB 3.0 port if available
4. **Check System Information**: Open System Information > USB and verify the device appears
5. **Install drivers**: Some devices require manufacturer drivers
6. **Restart CapturePlay**: The app detects devices on launch
7. **Check device compatibility**: Ensure the device is compatible with macOS

**For Continuity Camera specifically**:

1. **Check macOS version**: Continuity Camera requires macOS 13.0 (Ventura) or later
2. **Check iOS version**: iPhone must be running iOS 16.0 or later
3. **Verify Apple ID**: Both devices must be signed in to the same Apple ID with two-factor authentication
4. **Enable Handoff**: On iPhone: Settings > General > AirPlay & Handoff > Enable "Handoff" and "Continuity Camera"
5. **Check network**: Ensure both devices are on the same Wi-Fi network with Wi-Fi and Bluetooth enabled
6. **Disable VPNs**: VPNs can interfere with Continuity Camera — disable VPNs on both devices
7. **Disable AirPlay Receiver**: On Mac: System Settings > General > AirDrop & Handoff > Turn off "AirPlay Receiver"
8. **Position iPhone correctly**: iPhone should be locked, stable, and positioned with the rear cameras facing you in landscape
9. **Restart both devices**: Restart both iPhone and Mac if connection issues persist

### App Crashes or Freezes

**Problem**: CapturePlay crashes or becomes unresponsive.

**Solutions**:

1. **Check macOS version**: Ensure you're running macOS 12.4 or later
2. **Check device compatibility**: Some devices may cause issues
3. **Reset preferences**: Quit the app, delete the preferences file at `~/Library/Preferences/org.windholm.captureplay.plist`, then relaunch
4. **Check Console**: Open Console.app and check for error messages
5. **Reinstall**: Delete the app and reinstall from a fresh build

### Performance Issues

**Problem**: Video is choppy or laggy.

**Solutions**:

1. **Adjust Performance Mode**: Go to **CapturePlay > Settings** and try a lower performance mode:
   - If set to "High", try "Medium" or "Auto"
   - If set to "Medium", try "Low" for maximum smoothness
   - "Auto" mode will automatically detect slower systems and apply optimizations
2. **Close other applications**: Free up CPU and memory resources
3. **Check device resolution**: High-resolution devices require more processing power
4. **Lower frame rate**: Some devices allow frame rate adjustment (device-specific)
5. **Check USB bandwidth**: Use USB 3.0 ports for high-resolution devices
6. **Disable other video apps**: Close other apps using video capture devices
7. **Disable color correction**: If you're using color correction (brightness, contrast, hue), try resetting to defaults to reduce processing overhead

---

## Technical Details

### Video Format

- **Container**: MOV (QuickTime)
- **Video Codec**: H.264 (device-dependent)
- **Audio Codec**: AAC at 256 Kbps
- **Frame Rate**: Matches device configuration (typically 60fps or 59.94fps)
- **Resolution**: Native device resolution

### Image Format

- **Format**: PNG
- **Color Space**: RGB
- **Resolution**: Window resolution at time of capture

### File Naming

- **Images**: `CapturePlay Image YYYY-MM-DD at HH.mm.ss.png`
- **Videos**: `CapturePlay Video YYYY-MM-DD at HH.mm.ss.mov`

Both use 24-hour time format (HH.mm.ss).

### Preferences Storage

Preferences are stored in macOS UserDefaults, typically at:
```
~/Library/Preferences/org.windholm.captureplay.plist
```

---

## Credits

**CapturePlay**  
Version 3.5  
Copyright © 2025 Harald Striepe

**Original Quick Camera Code**  
Copyright © 2025 Simon Guest  
Licensed under Apache License 2.0  
[GitHub: quick-camera](https://github.com/simonguest/quick-camera)

**Acknowledgments**

CapturePlay includes code from Simon Guest's Quick Camera project, which provided the foundation for video capture and display functionality.

---

## License

This manual and the CapturePlay application are provided as-is. Please refer to the application's license for usage terms under Apache V2.0.

---

## Support

For issues, feature requests, or contributions, please refer to the project repository or contact the maintainer at hstriepe@mac.com

[GitHub]: https://github.com/hstriepe/CapturePlay
