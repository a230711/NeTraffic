import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: StatusPanel?
    var monitor = NetworkMonitor()
    var statsReader = StatsJSONReader()
    var cancellable: AnyCancellable?
    var disconnectionStartTime: Date? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.startMonitoring()
        
        // 初始化面板
        panel = StatusPanel(networkMonitor: monitor, statsReader: statsReader)
        
        statusItem = NSStatusBar.system.statusItem(withLength: 60)
        
        if let button = statusItem.button {
            button.action = #selector(togglePanel(_:))
            button.target = self
        }
        
        cancellable = monitor.$rxSpeed.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self = self, let button = self.statusItem.button else { return }
            
            let txSpeed = self.monitor.txSpeed
            let rxSpeed = self.monitor.rxSpeed
            
            // 判斷斷線狀態
            let isDisconnected = self.monitor.networkDevice == "-"
            if isDisconnected {
                if self.disconnectionStartTime == nil {
                    self.disconnectionStartTime = Date()
                }
            } else {
                self.disconnectionStartTime = nil
            }
            
            let absDuration = self.disconnectionStartTime != nil ? abs(self.disconnectionStartTime!.timeIntervalSinceNow) : 0
            let warningColor = self.getWarningColor(for: absDuration, isDisconnected: isDisconnected)
            
            let txString = self.formatSpeed(txSpeed)
            let rxString = self.formatSpeed(rxSpeed)
            
            button.image = self.createMenuBarImage(txString: txString, rxString: rxString, txSpeed: txSpeed, rxSpeed: rxSpeed, warningColor: warningColor)
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
        }
    }
    
    @objc func togglePanel(_ sender: AnyObject?) {
        guard let button = statusItem.button, let panel = panel else { return }
        
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            // 定位面板在按鈕下方
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
        if duration >= 1.5 * 60 { return NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.8, alpha: 1.0) } // 淡黃色
        
        return nil
    }

    func formatSpeed(_ bytesPerSec: UInt64) -> String {
        let kbps = Double(bytesPerSec) / 1024.0
        if kbps >= 1000 {
            let mbps = kbps / 1024.0
            return String(format: "%.1f MB/s", mbps)
        } else {
            return String(format: "%.0f KB/s", kbps)
        }
    }
    
    func createMenuBarImage(txString: String, rxString: String, txSpeed: UInt64, rxSpeed: UInt64, warningColor: NSColor?) -> NSImage {
        let width: CGFloat = 60
        let height: CGFloat = 22
        let image = NSImage(size: NSSize(width: width, height: height))
        
        image.lockFocus()
        
        // 繪製背景色（如果有警告）
        if let bgColor = warningColor {
            bgColor.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        
        // 文字與圖示顏色判定
        // 當背景為黃、橘、紅時，文字改為灰色；其餘（正常透明或黑色背景）則維持白色
        let isGrayText = (warningColor != nil && warningColor != .black)
        let textColor: NSColor = isGrayText ? .gray : .white
        let dotColorFactor: CGFloat = isGrayText ? 0.6 : 1.0 // 灰色文字時點也稍微變暗一點
        
        let txColor = (txSpeed == 0) ? textColor : NSColor.systemBlue
        txColor.withAlphaComponent(dotColorFactor).setFill()
        let txRect = NSRect(x: 2, y: 12.5, width: 5, height: 5)
        let txPath = NSBezierPath(ovalIn: txRect)
        txPath.fill()
        
        let rxColor = (rxSpeed == 0) ? textColor : NSColor.systemRed
        rxColor.withAlphaComponent(dotColorFactor).setFill()
        let rxRect = NSRect(x: 2, y: 3.5, width: 5, height: 5)
        let rxPath = NSBezierPath(ovalIn: rxRect)
        rxPath.fill()
        
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let txAttrStr = NSAttributedString(string: txString, attributes: attrs)
        let rxAttrStr = NSAttributedString(string: rxString, attributes: attrs)
        
        let txSize = txAttrStr.size()
        let rxSize = rxAttrStr.size()
        
        let txX = width - txSize.width - 2
        let rxX = width - rxSize.width - 2
        
        txAttrStr.draw(at: NSPoint(x: txX, y: 11.5))
        rxAttrStr.draw(at: NSPoint(x: rxX, y: 1.5))
        
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

class StatusPanel: NSPanel {
    init(networkMonitor: NetworkMonitor, statsReader: StatsJSONReader) {
        let contentView = ContentView(networkMonitor: networkMonitor, statsReader: statsReader)
        let hostingController = NSHostingController(rootView: contentView)
        
        // 獲取螢幕高度以計算安全上限
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let maxPanelHeight = screenHeight - 100
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 500),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        
        // 使用 Visual Effect View 營造毛玻璃質感
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16 // 增加圓角半徑
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
            hostingController.view.heightAnchor.constraint(lessThanOrEqualToConstant: maxPanelHeight)
        ])
    }
    
    override var canBecomeKey: Bool { return true }
    
    override func resignKey() {
        super.resignKey()
        self.orderOut(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
