3. - # Release Notes

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