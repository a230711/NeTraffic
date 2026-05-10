import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let pStyle = NSMutableParagraphStyle()
            pStyle.lineSpacing = -3
            pStyle.alignment = .right
            let text = "U 10K\nD 20K"
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            let attr = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: pStyle])
            button.attributedTitle = attr
        }
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
