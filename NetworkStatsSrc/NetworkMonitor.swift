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
    private var primaryInterfaceFromPath: String? = nil
    
    func startMonitoring() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            let connected = (path.status == .satisfied)
            let interfaceName = path.availableInterfaces.first?.name
            DispatchQueue.main.async {
                self?.isConnected = connected
                self?.primaryInterfaceFromPath = interfaceName
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitorQueue")
        pathMonitor?.start(queue: queue)
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateNetworkStats()
        }
        RunLoop.main.add(timer!, forMode: .common)
        updateNetworkStats()
    }
    
    private func getDefaultInterfaceAndGateway() -> (iface: String?, gateway: String?) {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["sh", "-c", "route -n get default"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            var iface: String? = nil
            var gateway: String? = nil
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("interface:") {
                    iface = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
                }
                if line.contains("gateway:") {
                    gateway = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
                }
            }
            return (iface, gateway)
        }
        return (nil, nil)
    }
    
    private func updateNetworkStats() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var activeInterface: String?
        var maxTraffic: UInt64 = 0
        
        let netInfo = getDefaultInterfaceAndGateway()
        if let iface = netInfo.iface {
            primaryInterfaceFromPath = iface
        }
        
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
                    rx += currentRx; tx += currentTx
                    
                    if let primary = primaryInterfaceFromPath, name == primary {
                        activeInterface = name
                        maxTraffic = UInt64.max
                    } else if activeInterface == nil || (currentRx + currentTx > maxTraffic) {
                        if activeInterface != primaryInterfaceFromPath {
                            maxTraffic = currentRx + currentTx
                            activeInterface = name
                        }
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        
        if let activeIf = activeInterface {
            updateDeviceInfo(interfaceName: activeIf, gateway: netInfo.gateway)
        } else {
            DispatchQueue.main.async {
                self.networkDevice = "-"; self.networkProvider = "-"
                self.connectionMethod = "-"; self.isConnected = false
            }
        }
        
        DispatchQueue.main.async {
            if activeInterface == nil { self.isConnected = false }
            if self.isFirstRun {
                self.lastRx = rx; self.lastTx = tx
                self.isFirstRun = false; return
            }
            let diffRx = rx >= self.lastRx ? rx - self.lastRx : 0
            let diffTx = tx >= self.lastTx ? tx - self.lastTx : 0
            self.rxSpeed = diffRx; self.txSpeed = diffTx
            self.lastRx = rx; self.lastTx = tx
            self.rxHistory.removeFirst(); self.rxHistory.append(Double(diffRx) / 1024.0)
            self.txHistory.removeFirst(); self.txHistory.append(Double(diffTx) / 1024.0)
        }
    }
    
    private func updateDeviceInfo(interfaceName: String, gateway: String?) {
        var rawName: String = "未知"
        var device: String = "-"
        var provider: String = "-" 
        var method: String = "Ethernet"
        
        // 1. 取得原始介面資訊與連線方式
        if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in interfaces {
                if let bsdName = SCNetworkInterfaceGetBSDName(interface), bsdName as String == interfaceName {
                    if let localizedName = SCNetworkInterfaceGetLocalizedDisplayName(interface) {
                        let hName = localizedName as String
                        rawName = hName
                        if hName.contains("iPhone") || hName.contains("USB") {
                            method = "USB"
                        } else if hName.contains("Wi-Fi") {
                            method = "Wi-Fi"
                            if let ssid = CWWiFiClient.shared().interface()?.ssid() { rawName = ssid }
                        }
                    }
                    break
                }
            }
        }
        
        // 針對 iPhone 熱點閘道器的特別標記 (覆蓋 rawName)
        if gateway == "172.20.10.1" {
            rawName = (interfaceName == "en0") ? "iPhone (Wi-Fi)" : "iPhone (USB)"
            method = (interfaceName == "en0") ? "Wi-Fi" : "USB"
        }
        
        // 2. 檢查自定義映射 (優先級最高)
        let mappings = UserDefaults.standard.dictionary(forKey: "NetworkMappings") as? [String: [String: String]] ?? [:]
        if let custom = mappings[rawName] {
            device = custom["device"] ?? "-"
            provider = custom["provider"] ?? "-"
        } 
        // 3. 智慧自動識別 (無映射時)
        else if gateway == "172.20.10.1" {
            device = "iPhone 16 Pro"
            provider = "中華電信"
            if method == "USB" { provider += " 有線" } else { provider += " 無線" }
        } else if rawName == "22126RN91Y" || rawName.contains("Redmi") || rawName.contains("Starlink") {
            device = "Redmi 12C"
            provider = "星鏈"
        }
        
        // 針對自動識別出的 rawName 補齊 iPhone 後綴 (如果剛好名稱包含 iPhone 但不是走閘道器)
        if device == "-" && rawName.contains("iPhone") {
            device = "iPhone 16 Pro"
            provider = "中華電信"
            if method == "USB" { provider += " 有線" } else { provider += " 無線" }
        }
        
        DispatchQueue.main.async {
            self.networkDevice = device
            self.networkProvider = provider
            self.connectionMethod = method
            UserDefaults.standard.set(rawName, forKey: "CurrentRawNetworkName")
        }
    }
    
    func saveCustomMapping(device: String, provider: String) {
        let rawName = UserDefaults.standard.string(forKey: "CurrentRawNetworkName") ?? ""
        guard !rawName.isEmpty else { return }
        var mappings = UserDefaults.standard.dictionary(forKey: "NetworkMappings") as? [String: [String: String]] ?? [:]
        var originalProviderInJSON = provider
        if rawName.contains("22126RN91Y") || rawName.contains("iPhone") { 
            originalProviderInJSON = (rawName.contains("22126RN91Y")) ? "Starlink (星鏈)" : "iPhone 16 Pro (中華電信)" 
        }
        mappings[rawName] = ["device": device, "provider": provider, "originalProviderInJSON": originalProviderInJSON]
        UserDefaults.standard.set(mappings, forKey: "NetworkMappings")
        self.networkDevice = device
        self.networkProvider = provider
    }
}
