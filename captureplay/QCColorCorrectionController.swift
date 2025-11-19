// Copyright H. Striepe - 2025

import Cocoa

// MARK: - QCColorCorrectionControllerDelegate Protocol
protocol QCColorCorrectionControllerDelegate: AnyObject {
    func colorCorrectionController(_ controller: QCColorCorrectionController, didChangeBrightness brightness: Float, contrast: Float, hue: Float)
}

// MARK: - QCColorCorrectionController Class
class QCColorCorrectionController: NSWindowController {
    
    // MARK: - Properties
    weak var delegate: QCColorCorrectionControllerDelegate?
    var deviceName: String? {
        didSet {
            updateUIForCurrentDevice()
        }
    }
    
    @IBOutlet weak var brightnessSlider: NSSlider!
    @IBOutlet weak var contrastSlider: NSSlider!
    @IBOutlet weak var hueSlider: NSSlider!
    @IBOutlet weak var brightnessLabel: NSTextField!
    @IBOutlet weak var contrastLabel: NSTextField!
    @IBOutlet weak var hueLabel: NSTextField!
    @IBOutlet weak var resetButton: NSButton!
    @IBOutlet weak var closeButton: NSButton!
    
    private var brightnessValueLabel: NSTextField?
    private var contrastValueLabel: NSTextField?
    private var hueValueLabel: NSTextField?
    
    // MARK: - Initialization
    override init(window: NSWindow?) {
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    convenience init(deviceName: String? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Color Correction"
        window.center()
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
        self.deviceName = deviceName
        setupUI()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // Brightness
        let brightnessLabel = NSTextField(labelWithString: "Brightness:")
        brightnessLabel.frame = NSRect(x: 20, y: 150, width: 100, height: 17)
        contentView.addSubview(brightnessLabel)
        self.brightnessLabel = brightnessLabel
        
        let brightnessValueLabel = NSTextField(labelWithString: "0.0")
        brightnessValueLabel.frame = NSRect(x: 320, y: 150, width: 60, height: 17)
        brightnessValueLabel.alignment = .right
        contentView.addSubview(brightnessValueLabel)
        
        let brightnessSlider = NSSlider(frame: NSRect(x: 120, y: 152, width: 200, height: 16))
        brightnessSlider.minValue = -1.0
        brightnessSlider.maxValue = 1.0
        // Load device-specific or default value
        let initialBrightness = deviceName.map { QCSettingsManager.shared.getColorCorrection(forDevice: $0).brightness } ?? QCSettingsManager.shared.brightness
        brightnessSlider.doubleValue = Double(initialBrightness)
        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged(_:))
        brightnessSlider.isContinuous = true
        contentView.addSubview(brightnessSlider)
        self.brightnessSlider = brightnessSlider
        self.brightnessValueLabel = brightnessValueLabel
        
        // Update value label
        brightnessValueLabel.stringValue = String(format: "%.2f", brightnessSlider.doubleValue)
        
        // Contrast
        let contrastLabel = NSTextField(labelWithString: "Contrast:")
        contrastLabel.frame = NSRect(x: 20, y: 120, width: 100, height: 17)
        contentView.addSubview(contrastLabel)
        self.contrastLabel = contrastLabel
        
        let contrastValueLabel = NSTextField(labelWithString: "1.0")
        contrastValueLabel.frame = NSRect(x: 320, y: 120, width: 60, height: 17)
        contrastValueLabel.alignment = .right
        contentView.addSubview(contrastValueLabel)
        
        let contrastSlider = NSSlider(frame: NSRect(x: 120, y: 122, width: 200, height: 16))
        contrastSlider.minValue = 0.0
        contrastSlider.maxValue = 2.0
        // Load device-specific or default value
        let initialContrast = deviceName.map { QCSettingsManager.shared.getColorCorrection(forDevice: $0).contrast } ?? QCSettingsManager.shared.contrast
        contrastSlider.doubleValue = Double(initialContrast)
        contrastSlider.target = self
        contrastSlider.action = #selector(contrastChanged(_:))
        contrastSlider.isContinuous = true
        contentView.addSubview(contrastSlider)
        self.contrastSlider = contrastSlider
        self.contrastValueLabel = contrastValueLabel
        
        // Update value label
        contrastValueLabel.stringValue = String(format: "%.2f", contrastSlider.doubleValue)
        
        // Hue
        let hueLabel = NSTextField(labelWithString: "Hue:")
        hueLabel.frame = NSRect(x: 20, y: 90, width: 100, height: 17)
        contentView.addSubview(hueLabel)
        self.hueLabel = hueLabel
        
        let hueValueLabel = NSTextField(labelWithString: "0.0")
        hueValueLabel.frame = NSRect(x: 320, y: 90, width: 60, height: 17)
        hueValueLabel.alignment = .right
        contentView.addSubview(hueValueLabel)
        
        let hueSlider = NSSlider(frame: NSRect(x: 120, y: 92, width: 200, height: 16))
        hueSlider.minValue = -180.0
        hueSlider.maxValue = 180.0
        // Load device-specific or default value
        let initialHue = deviceName.map { QCSettingsManager.shared.getColorCorrection(forDevice: $0).hue } ?? QCSettingsManager.shared.hue
        hueSlider.doubleValue = Double(initialHue)
        hueSlider.target = self
        hueSlider.action = #selector(hueChanged(_:))
        hueSlider.isContinuous = true
        contentView.addSubview(hueSlider)
        self.hueSlider = hueSlider
        self.hueValueLabel = hueValueLabel
        
        // Update value label
        hueValueLabel.stringValue = String(format: "%.1f", hueSlider.doubleValue)
        
        // Reset button (bottom left)
        let resetButton = NSButton(title: "Reset", target: self, action: #selector(reset(_:)))
        resetButton.frame = NSRect(x: 20, y: 20, width: 80, height: 32)
        contentView.addSubview(resetButton)
        self.resetButton = resetButton
        
        // Close button (bottom right)
        let closeButton = NSButton(title: "Close", target: self, action: #selector(close(_:)))
        closeButton.frame = NSRect(x: 300, y: 20, width: 80, height: 32)
        contentView.addSubview(closeButton)
        self.closeButton = closeButton
    }
    
    // MARK: - Actions
    @objc private func brightnessChanged(_ sender: NSSlider) {
        let value = Float(sender.doubleValue)
        let currentContrast = Float(contrastSlider?.doubleValue ?? 1.0)
        let currentHue = Float(hueSlider?.doubleValue ?? 0.0)
        
        if let deviceName = deviceName {
            QCSettingsManager.shared.setColorCorrection(forDevice: deviceName, brightness: value, contrast: currentContrast, hue: currentHue)
        } else {
            QCSettingsManager.shared.setBrightness(value)
        }
        
        brightnessValueLabel?.stringValue = String(format: "%.2f", sender.doubleValue)
        delegate?.colorCorrectionController(self, didChangeBrightness: value, contrast: currentContrast, hue: currentHue)
    }
    
    @objc private func contrastChanged(_ sender: NSSlider) {
        let value = Float(sender.doubleValue)
        let currentBrightness = Float(brightnessSlider?.doubleValue ?? 0.0)
        let currentHue = Float(hueSlider?.doubleValue ?? 0.0)
        
        if let deviceName = deviceName {
            QCSettingsManager.shared.setColorCorrection(forDevice: deviceName, brightness: currentBrightness, contrast: value, hue: currentHue)
        } else {
            QCSettingsManager.shared.setContrast(value)
        }
        
        contrastValueLabel?.stringValue = String(format: "%.2f", sender.doubleValue)
        delegate?.colorCorrectionController(self, didChangeBrightness: currentBrightness, contrast: value, hue: currentHue)
    }
    
    @objc private func hueChanged(_ sender: NSSlider) {
        let value = Float(sender.doubleValue)
        let currentBrightness = Float(brightnessSlider?.doubleValue ?? 0.0)
        let currentContrast = Float(contrastSlider?.doubleValue ?? 1.0)
        
        if let deviceName = deviceName {
            QCSettingsManager.shared.setColorCorrection(forDevice: deviceName, brightness: currentBrightness, contrast: currentContrast, hue: value)
        } else {
            QCSettingsManager.shared.setHue(value)
        }
        
        hueValueLabel?.stringValue = String(format: "%.1f", sender.doubleValue)
        delegate?.colorCorrectionController(self, didChangeBrightness: currentBrightness, contrast: currentContrast, hue: value)
    }
    
    @objc private func reset(_ sender: NSButton) {
        // Reset to defaults: brightness 0.0, contrast 1.0, hue 0.0
        brightnessSlider?.doubleValue = 0.0
        contrastSlider?.doubleValue = 1.0
        hueSlider?.doubleValue = 0.0
        
        if let deviceName = deviceName {
            QCSettingsManager.shared.setColorCorrection(forDevice: deviceName, brightness: 0.0, contrast: 1.0, hue: 0.0)
        } else {
            QCSettingsManager.shared.setBrightness(0.0)
            QCSettingsManager.shared.setContrast(1.0)
            QCSettingsManager.shared.setHue(0.0)
        }
        QCSettingsManager.shared.saveSettings()
        
        // Update value labels
        brightnessValueLabel?.stringValue = "0.00"
        contrastValueLabel?.stringValue = "1.00"
        hueValueLabel?.stringValue = "0.0"
        
        delegate?.colorCorrectionController(self, didChangeBrightness: 0.0, contrast: 1.0, hue: 0.0)
    }
    
    private func updateUIForCurrentDevice() {
        guard brightnessSlider != nil, contrastSlider != nil, hueSlider != nil else { return }
        
        let correction = deviceName.map { QCSettingsManager.shared.getColorCorrection(forDevice: $0) } ?? (brightness: 0.0, contrast: 1.0, hue: 0.0)
        
        brightnessSlider?.doubleValue = Double(correction.brightness)
        contrastSlider?.doubleValue = Double(correction.contrast)
        hueSlider?.doubleValue = Double(correction.hue)
        
        brightnessValueLabel?.stringValue = String(format: "%.2f", correction.brightness)
        contrastValueLabel?.stringValue = String(format: "%.2f", correction.contrast)
        hueValueLabel?.stringValue = String(format: "%.1f", correction.hue)
        
        // Notify delegate to apply changes
        delegate?.colorCorrectionController(self, didChangeBrightness: correction.brightness, contrast: correction.contrast, hue: correction.hue)
    }
    
    @objc private func close(_ sender: NSButton) {
        window?.close()
    }
    
    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
    }
}

