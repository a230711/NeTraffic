import Foundation
import Darwin
import SystemConfiguration
import CoreWLAN
import UserNotifications
import Network

class NetworkMonitor: ObservableObject {
    @Published var rxSpeed: UInt64 = 0
    @Published var txSpeed: UInt64 = 0
    
    // Store history in KB for charts
    @Published var rxHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var txHistory: [Double] = Array(repeating: 0, count: 60)
    
    // New Fields
    @Published var networkDevice: String = "未連接"
    @Published var networkProvider: String = "未偵測"
    @Published var connectionMethod: String = "未偵測"
    @Published var isConnected: Bool = false
    
    private var notifiedRawNames = Set<String>()
    
    private var timer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var lastRx: UInt64 = 0
    private var lastTx: UInt64 = 0
    private var isFirstRun = true
    
    func startMonitoring() {
        // 請求通知權限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        // 使用 NWPathMonitor 監控網路連線狀態
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            let connected = (path.status == .satisfied)
            DispatchQueue.main.async {
                self?.isConnected = connected
                print("DEBUG: NWPathMonitor Status -> \(connected ? "Connected" : "Disconnected") (Path: \(String(describing: path)))")
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitorQueue")
        pathMonitor?.start(queue: queue)
        
        // Use .common runloop mode to ensure the timer fires even when a popover/menu is active
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateNetworkStats()
        }
        RunLoop.main.add(timer!, forMode: .common)
        updateNetworkStats() // Initial fetch
    }
    
    private func updateNetworkStats() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var activeInterface: String?
        var maxTraffic: UInt64 = 0
        
        // 第一步：找出所有具有 IP 位址的介面名稱
        var interfacesWithIP = Set<String>()
        var p = ifaddr
        while p != nil {
            let interface = p!.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                interfacesWithIP.insert(name)
            }
            p = interface.ifa_next
        }
        
        // 第二步：從具有 IP 的介面中，找出流量最大的實體介面 (en*)
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            let interface = ptr!.pointee
            let name = String(cString: interface.ifa_name)
            let family = interface.ifa_addr.pointee.sa_family
            let flags = Int32(interface.ifa_flags)
            
            if name.hasPrefix("en"), family == UInt8(AF_LINK), 
               interfacesWithIP.contains(name),
               (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0 {
                
                if let data = interface.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    let currentRx = UInt64(networkData.ifi_ibytes)
                    let currentTx = UInt64(networkData.ifi_obytes)
                    rx += currentRx
                    tx += currentTx
                    
                    if activeInterface == nil || (currentRx + currentTx > maxTraffic) {
                        maxTraffic = currentRx + currentTx
                        activeInterface = name
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        
        if let activeIf = activeInterface {
            updateDeviceInfo(interfaceName: activeIf)
        } else {
            DispatchQueue.main.async {
                self.networkDevice = "-"
                self.networkProvider = "-"
                self.connectionMethod = "-"
                self.isConnected = false
            }
        }
        
        DispatchQueue.main.async {
            // 如果沒抓到 activeInterface，表示實體層級斷開
            if activeInterface == nil {
                self.isConnected = false
            }
            
            if self.isFirstRun {
                self.lastRx = rx
                self.lastTx = tx
                self.isFirstRun = false
                return
            }
            
            let diffRx = rx >= self.lastRx ? rx - self.lastRx : 0
            let diffTx = tx >= self.lastTx ? tx - self.lastTx : 0
            
            self.rxSpeed = diffRx
            self.txSpeed = diffTx
            
            self.lastRx = rx
            self.lastTx = tx
            
            self.rxHistory.removeFirst()
            self.rxHistory.append(Double(diffRx) / 1024.0) // Convert to KB for chart
            self.txHistory.removeFirst()
            self.txHistory.append(Double(diffTx) / 1024.0)
        }
    }
    
    private func updateDeviceInfo(interfaceName: String) {
        var rawName: String = "未知"
        var device: String = "-"
        var provider: String = "-" 
        var method: String = "Ethernet"
        
        // 嘗試從 SystemConfiguration 獲取詳細資訊
        if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in interfaces {
                if let bsdName = SCNetworkInterfaceGetBSDName(interface), bsdName as String == interfaceName {
                    // 獲取硬體埠名稱 (例如 "Wi-Fi" 或 "22126RN91Y")
                    if let localizedName = SCNetworkInterfaceGetLocalizedDisplayName(interface) {
                        let hName = localizedName as String
                        rawName = hName
                        
                        if hName.contains("iPhone") || hName.contains("USB") {
                            method = "USB"
                        } else if hName.contains("Wi-Fi") {
                            method = "Wi-Fi"
                            if let ssid = CWWiFiClient.shared().interface()?.ssid() {
                                rawName = ssid
                            } else {
                                // 備選方案：使用 shell 指令獲取 SSID
                                let task = Process()
                                task.launchPath = "/usr/sbin/networksetup"
                                task.arguments = ["-getairportnetwork", interfaceName]
                                let pipe = Pipe()
                                task.standardOutput = pipe
                                task.launch()
                                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                                if let output = String(data: data, encoding: .utf8), output.contains(": ") {
                                    rawName = output.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawName
                                }
                            }
                        }
                    }
                    
                    // 進階檢查：從「網路服務」名稱判斷 (例如 "Redmi 12C USB網路")
                    if let prefs = SCPreferencesCreate(nil, "NeTraffic" as CFString, nil),
                       let sets = SCNetworkSetCopyCurrent(prefs),
                       let services = SCNetworkSetCopyServices(sets) as? [SCNetworkService] {
                        for service in services {
                            if let sInterface = SCNetworkServiceGetInterface(service),
                               let sBsdName = SCNetworkInterfaceGetBSDName(sInterface),
                               sBsdName as String == interfaceName {
                                if let sName = SCNetworkServiceGetName(service) as String? {
                                    // 如果服務名稱包含 USB，則判定為 USB 連線
                                    if sName.contains("USB") {
                                        method = "USB"
                                    }
                                    // 如果硬體標籤是奇怪的編碼，改用較好讀的服務名稱作為原始標籤
                                    if rawName.count > 15 || rawName == interfaceName {
                                        rawName = sName
                                    }
                                }
                                break
                            }
                        }
                    }
                    break
                }
            }
        }
        
        // 套用自定義映射
        let mappings = UserDefaults.standard.dictionary(forKey: "NetworkMappings") as? [String: [String: String]] ?? [:]
        if let custom = mappings[rawName] {
            device = custom["device"] ?? "-"
            provider = custom["provider"] ?? "-"
            print("Mapping found for \(rawName): \(device), \(provider)")
        } else {
            // 未知設備，發送通知
            print("No mapping for \(rawName)")
            if !notifiedRawNames.contains(rawName) && rawName != "未知" {
                sendNewConnectionNotification(rawName: rawName)
                notifiedRawNames.insert(rawName)
            }
        }
        
        DispatchQueue.main.async {
            self.networkDevice = device
            self.networkProvider = provider
            self.connectionMethod = method
            UserDefaults.standard.set(rawName, forKey: "CurrentRawNetworkName")
        }
    }
    
    private func sendNewConnectionNotification(rawName: String) {
        let content = UNMutableNotificationContent()
        content.title = "偵測到新網路設備"
        content.body = "原始名稱：\(rawName)\n請點擊內容視窗進行自定義標籤。"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func saveCustomMapping(device: String, provider: String) {
        let rawName = UserDefaults.standard.string(forKey: "CurrentRawNetworkName") ?? ""
        guard !rawName.isEmpty else { return }
        
        var mappings = UserDefaults.standard.dictionary(forKey: "NetworkMappings") as? [String: [String: String]] ?? [:]
        mappings[rawName] = ["device": device, "provider": provider]
        UserDefaults.standard.set(mappings, forKey: "NetworkMappings")
        
        // 立即更新 UI
        self.networkDevice = device
        self.networkProvider = provider
    }
}
