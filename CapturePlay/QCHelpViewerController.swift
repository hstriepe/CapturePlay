//
//  QCHelpViewerController.swift
//  CapturePlay
//
//  Created on 11/14/25.
//

import Cocoa
import WebKit

protocol QCHelpViewerDelegate: AnyObject {
    func helpViewerDidClose(_ helpViewer: QCHelpViewerController)
}

class QCHelpViewerController: NSWindowController {
    
    weak var delegate: QCHelpViewerDelegate?
    
    private var webView: WKWebView!
    
    convenience init() {
        // Create a window with WebView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CapturePlay Help"
        window.center()
        window.setFrameAutosaveName("HelpWindow")
        
        self.init(window: window)
        
        // Create WebView
        let contentView = window.contentView!
        webView = WKWebView(frame: contentView.bounds, configuration: WKWebViewConfiguration())
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        
        contentView.addSubview(webView)
        
        // Set window delegate
        window.delegate = self
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        loadHelpContent()
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        
        // Load content if not already loaded
        if webView.url == nil {
            loadHelpContent()
        }
    }
    
    private func loadHelpContent() {
        // Look for MANUAL.html in the bundle Resources
        var htmlURL: URL?
        
        if let manualURL = Bundle.main.url(forResource: "MANUAL", withExtension: "html") {
            htmlURL = manualURL
        } else if let resourcesPath = Bundle.main.resourcePath {
            let htmlPath = (resourcesPath as NSString).appendingPathComponent("MANUAL.html")
            if FileManager.default.fileExists(atPath: htmlPath) {
                htmlURL = URL(fileURLWithPath: htmlPath)
            }
        }
        
        guard let url = htmlURL else {
            showError("The help manual could not be found. Please ensure MANUAL.html is included in the app bundle.")
            return
        }
        
        // Read and load HTML
        do {
            let htmlData = try Data(contentsOf: url)
            guard let htmlString = String(data: htmlData, encoding: .utf8) else {
                showError("The help manual could not be decoded. The file may be corrupted.")
                return
            }
            
            webView.loadHTMLString(htmlString, baseURL: nil)
        } catch {
            showError("Could not read the help manual: \(error.localizedDescription)")
        }
    }
    
    private func showError(_ message: String) {
        let errorHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Help Not Available</title>
            <style>
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
                    padding: 40px; 
                    background-color: #ffffff;
                    color: #333333;
                }
                h1 { color: #d00; margin-top: 0; }
            </style>
        </head>
        <body>
            <h1>Help Not Available</h1>
            <p>\(message)</p>
        </body>
        </html>
        """
        webView.loadHTMLString(errorHTML, baseURL: nil)
    }
}

extension QCHelpViewerController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        delegate?.helpViewerDidClose(self)
    }
}

extension QCHelpViewerController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Only show error for non-cancelled navigations
        let nsError = error as NSError
        if nsError.code != NSURLErrorCancelled {
            showError("Failed to load help content: \(error.localizedDescription)")
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Only show error for non-cancelled navigations
        let nsError = error as NSError
        if nsError.code != NSURLErrorCancelled {
            showError("Failed to load help content: \(error.localizedDescription)")
        }
    }
}
