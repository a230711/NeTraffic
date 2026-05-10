import Cocoa
import SwiftUI
import Combine

class MenuBarView: NSView {
    var txString: String = "0 KB/s"
    var rxString: String = "0 KB/s"
    var txSpeed: UInt64 = 0
    var rxSpeed: UInt64 = 0
    var warningColor: NSColor? = nil
    
    func update(txString: String, rxString: String, txSpeed: UInt64, rxSpeed: UInt64, warningColor: NSColor?) {
        self.txString = txString
        self.rxString = rxString
        self.txSpeed = txSpeed
        self.rxSpeed = rxSpeed
        self.warningColor = warningColor
        self.needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // 1. 繪製背景 (圓角色塊風格)
        if let bgColor = warningColor {
            bgColor.setFill()
            // 上下縮排 2 像素，左右縮排 1 像素，產生漂浮感
            let pillRect = bounds.insetBy(dx: 1, dy: 2)
            let path = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)
            path.fill()
        }
        
        // 2. 顏色判斷
        let isWarning = (warningColor != nil)
        let isBlackBG = (warningColor == .black)
        let textColor: NSColor = (isWarning && !isBlackBG) ? .gray : .white
        let dotColorFactor: CGFloat = (isWarning && !isBlackBG) ? 0.6 : 1.0
        
        // 3. 繪製 TX 點
        let txColor = (txSpeed == 0) ? textColor : NSColor.systemBlue
        txColor.withAlphaComponent(dotColorFactor).setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 12.5, width: 5, height: 5)).fill()
        
        // 4. 繪製 RX 點
        let rxColor = (rxSpeed == 0) ? textColor : NSColor.systemRed
        rxColor.withAlphaComponent(dotColorFactor).setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 3.5, width: 5, height: 5)).fill()
        
        // 5. 繪製文字
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        
        let txAttr = NSAttributedString(string: txString, attributes: attrs)
        let rxAttr = NSAttributedString(string: rxString, attributes: attrs)
        
        txAttr.draw(at: NSPoint(x: bounds.width - txAttr.size().width - 2, y: 11.5))
        rxAttr.draw(at: NSPoint(x: bounds.width - rxAttr.size().width - 2, y: 1.5))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menuBarView: MenuBarView!
    var panel: StatusPanel?
    var monitor = NetworkMonitor()
    var statsReader = StatsJSONReader()
    var cancellable: AnyCancellable?
    var warningTimer: Timer?
    var disconnectionStartTime: Date? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.startMonitoring()
        panel = StatusPanel(networkMonitor: monitor, statsReader: statsReader)
        
        statusItem = NSStatusBar.system.statusItem(withLength: 60)
        
        if let button = statusItem.button {
            menuBarView = MenuBarView(frame: button.bounds)
            button.addSubview(menuBarView)
            
            button.action = #selector(togglePanel(_:))
            button.target = self
        }
        
        cancellable = monitor.$rxSpeed.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateUI()
        }
        
        warningTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateUI()
        }
        RunLoop.main.add(warningTimer!, forMode: .common)
    }
    
    func updateUI() {
        guard let _ = statusItem.button else { return }
        
        // 優先以 isConnected 判斷，避免設備名稱更新延遲
        let isDisconnected = !self.monitor.isConnected
        
        if isDisconnected {
            if self.disconnectionStartTime == nil {
                self.disconnectionStartTime = Date()
            }
        } else {
            self.disconnectionStartTime = nil
        }
        
        let duration = self.disconnectionStartTime != nil ? abs(self.disconnectionStartTime!.timeIntervalSinceNow) : 0
        let warningColor = self.getWarningColor(for: duration, isDisconnected: isDisconnected)
        
        let txString = self.formatSpeed(monitor.txSpeed)
        let rxString = self.formatSpeed(monitor.rxSpeed)
        
        menuBarView.update(txString: txString, rxString: rxString, txSpeed: monitor.txSpeed, rxSpeed: monitor.rxSpeed, warningColor: warningColor)
    }
    
    @objc func togglePanel(_ sender: AnyObject?) {
        guard let button = statusItem.button, let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            let buttonFrame = button.window?.frame ?? .zero
            let panelFrame = panel.frame
            let x = buttonFrame.origin.x + (buttonFrame.width / 2) - (panelFrame.width / 2)
            let y = buttonFrame.origin.y - panelFrame.height - 5
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }
    
    func getWarningColor(for duration: TimeInterval, isDisconnected: Bool) -> NSColor? {
        guard isDisconnected else { return nil }
        
        if duration >= 40 * 60 { return .black }
        if duration >= 30 * 60 { return .systemRed }
        if duration >= 10 * 60 { return .systemOrange }
        if duration >= 5 * 60 { return .systemYellow }
        if duration >= 1.5 * 60 { 
            return NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.8, alpha: 1.0) // 淡黃色 (#FFFFCC)
        }
        
        return nil
    }

    func formatSpeed(_ bytesPerSec: UInt64) -> String {
        let kbps = Double(bytesPerSec) / 1024.0
        if kbps >= 1000 {
            return String(format: "%.1f MB/s", kbps / 1024.0)
        } else {
            return String(format: "%.0f KB/s", kbps)
        }
    }
}

class StatusPanel: NSPanel {
    init(networkMonitor: NetworkMonitor, statsReader: StatsJSONReader) {
        let contentView = ContentView(networkMonitor: networkMonitor, statsReader: statsReader)
        let hostingController = NSHostingController(rootView: contentView)
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 500),
                   styleMask: [.nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true
        self.contentView = visualEffectView
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hostingController.view.widthAnchor.constraint(equalToConstant: 340),
            hostingController.view.heightAnchor.constraint(lessThanOrEqualToConstant: screenHeight - 100)
        ])
    }
    override var canBecomeKey: Bool { return true }
    override func resignKey() { super.resignKey() ; self.orderOut(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
