# Release Notes

#### Version 3.5.6 (187 - internal) - 11-27-25

1. New icon.
2. Display Sleep Prevention - menu change and internal state fixes.
3. Code cleanup.
4. Refactored all names and internal code prefixes from QC to CP.
5. Further performance optimizations based on system capability. Auto mode can be overridden in Settings.
6. Some generic capture devices have an odd audio sample rate. We now convert to 48Khz in those cases for video-audio recording using AAC.
7. Settings item cleanup.
8. Align entitlements with App Store requirements.
9. Bug fixes, including random display blanking on recording and Notification delays.



#### Version 3.4 (136 - internal) - 11-20-25

  1. Translucent, hidden window title bar
  2. Video capture control start button hidden with title bar
  3. Some deprecations fixed
  4. Resource changes in bundle to prep for potential localization
  5. Bug fixes

#### Version 3.3 (126 - internal) - 11-18-25

  1. Added Video control for brightness, contrast, and hue
     1. Saved separately for each device
     2. Has a reset button
  2. Video on-screen Capture controls
     1. Appear on first capture.
     2. Settings dialog updated
        1. Disable Video Capture overlay buttons.
  3. New icon.
  4. Bug fixes

#### Version 3.2 (117 - internal) - 11-17-25

  1. Settings dialog updated
     1. Video > Image visibility is now toggled and visible by default
     1. Edit>Copy now captures window to clipboard
     1. Some key shortcuts have been reassigned for efficiency

#### Version 3.1 (106 - internal) - 11-15-25

  1. Menu Cleanup and Simplification

#### Version 3.0 (94) - 11-15-25

  1. Finished Refactoring — Extracted functionality from QCAppDelegate into manager classes:
  
     - QCWindowManager
     
     - QCCaptureFileManager
     
     - QCNotificationManager
     
     - QCDisplaySleepManager
     
     - QCPreferencesController
  
  2. Build System — Fixed Xcode project configuration, build number synchronization, and Info.plist handling
  
  3. Audio/Video Capture — Fixed device format configuration, frame rate handling, and audio session management
  
  4. Help System — Created and integrated a help manual system:
  
     - Created QCHelpViewerController with WKWebView
     
     - Integrated HTML manual display
     
     - Fixed sandbox issues and WebView rendering problems
     
     - Cleaned up and optimized the code
  
  5. Bug Fixes — Resolved multiple issues, including warnings, deprecated API usage, and various runtime problems

#### Version 2.8 (90) - 11-14-25

  1. Performance improved.
  
     - Tested - smoother frame rates:
     
       - El Gato Cam Link 4K on M1 Ultra - might not be as smooth on slower systems.
       
       - AVerMedia 4K HDMI GC553Pro Live Gamer Ultra S - M4 Pro mini. Has better performance on slower Macs.
  
  2. First refactoring into separate delegate files.
  
  3. Basic Feature Set complete:
  
     - Audio routing from any input to any output.
     
     - Mute and volume controls.
     
     - Image and video capture through shortcut keys.
     
     - The directory can be changed in Settings.
     
     - Notifications for key events.
     
     - Ability to disable Display Sleep.
     
     - Full screen disables Display Sleep and hides the cursor.
     
     - User Settings are retained.
