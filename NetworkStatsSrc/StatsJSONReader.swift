import Foundation

struct ProviderStats: Identifiable {
    let name: String
    var id: String { name } // 使用名稱作為穩定 ID
    let repeaterStr: String
    let macStr: String
    let othersStr: String
    var subStats: [ProviderStats] = []
}

class StatsJSONReader: ObservableObject {
    @Published var totalRepeater: String = "0 KB"
    @Published var totalMac: String = "0 KB"
    @Published var totalOthers: String = "0 KB"
    @Published var allProviders: [ProviderStats] = []
    
    private let statsURL = URL(fileURLWithPath: "/Users/changkueichen/Program/Shell/ChangeWiFi/usage_stats.json")
    
    private func formatBytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1048576 {
            return String(format: "%.1f KB", b / 1024.0)
        } else if b < 1073741824 {
            return String(format: "%.2f MB", b / 1048576.0)
        } else {
            return String(format: "%.2f GB", b / 1073741824.0)
        }
    }
    
    func refreshStats(providerFilter: String? = nil) {
        print("Refreshing stats with filter: \(providerFilter ?? "nil")")
        guard let data = try? Data(contentsOf: statsURL) else {
            print("Failed to load stats file at \(statsURL.path)")
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let currentMonth = formatter.string(from: Date())
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let monthly = json["monthly"] as? [String: [String: Any]],
               let currentMonthData = monthly[currentMonth] as? [String: [String: Any]] {
                
                var rTotal: Int64 = 0
                var mTotal: Int64 = 0
                var oTotal: Int64 = 0
                
                let mappings = UserDefaults.standard.dictionary(forKey: "NetworkMappings") as? [String: [String: String]] ?? [:]
                var providerOverrides: [String: String] = [:]
                var deviceOverrides: [String: String] = [:]
                
                for (_, map) in mappings {
                    if let original = map["originalProviderInJSON"] {
                        if let customP = map["provider"] { providerOverrides[original] = customP }
                        if let customD = map["device"] { deviceOverrides[original] = customD }
                    }
                }
                
                // 層級歸類：[父項目名稱: (總流量, [子項目列表])]
                var hierarchicalStats: [String: (r: Int64, m: Int64, o: Int64, subs: [String: (r: Int64, m: Int64, o: Int64)])] = [:]
                
                let filter = (providerFilter == nil || providerFilter == "-" || providerFilter == "未偵測") ? nil : providerFilter
                
                for (key, statsDict) in currentMonthData {
                    let r = (statsDict["repeater_total"] as? NSNumber)?.int64Value ?? 0
                    let m = (statsDict["mac_total"] as? NSNumber)?.int64Value ?? 0
                    let o = (statsDict["others"] as? NSNumber)?.int64Value ?? 0
                    
                    // 1. 判定父項目名稱 (不含 有線/無線)
                    let baseKey = key.replacingOccurrences(of: " 有線", with: "").replacingOccurrences(of: " 無線", with: "")
                    let customP = providerOverrides[baseKey] ?? baseKey
                    let customD = deviceOverrides[baseKey] ?? "-"
                    let parentName = (customD != "-" && customD != "") ? "\(customD) (\(customP))" : customP
                    
                    // 2. 判定子項目名稱 (純 USB / WiFi / Other)
                    var subName = "Other"
                    if key.contains("有線") { subName = "USB" }
                    else if key.contains("無線") { subName = "WiFi" }
                    
                    // 初始化父項目
                    if hierarchicalStats[parentName] == nil {
                        hierarchicalStats[parentName] = (r: 0, m: 0, o: 0, subs: [:])
                    }
                    
                    // 累加父項目總計
                    hierarchicalStats[parentName]!.r += r
                    hierarchicalStats[parentName]!.m += m
                    hierarchicalStats[parentName]!.o += o
                    
                    // 累加子項目
                    let currentSub = hierarchicalStats[parentName]!.subs[subName] ?? (r: 0, m: 0, o: 0)
                    hierarchicalStats[parentName]!.subs[subName] = (r: currentSub.r + r, m: currentSub.m + m, o: currentSub.o + o)
                    
                    // 處理全局過濾器 (改良比對邏輯)
                    if let f = filter {
                        // 將過濾器與 Key 都轉為小寫並移除空白進行模糊比對
                        let cleanKey = key.lowercased().replacingOccurrences(of: " ", with: "")
                        let cleanFilter = f.lowercased().replacingOccurrences(of: " ", with: "")
                        let cleanParent = parentName.lowercased().replacingOccurrences(of: " ", with: "")
                        
                        if cleanKey.contains(cleanFilter) || cleanParent.contains(cleanFilter) {
                            rTotal += r; mTotal += m; oTotal += o
                        }
                    } else {
                        rTotal += r; mTotal += m; oTotal += o
                    }
                }
                
                // 轉換為 ProviderStats 陣列
                var tempProviders: [ProviderStats] = []
                for (name, data) in hierarchicalStats {
                    var subStats: [ProviderStats] = []
                    // 如果只有一個子項目且名稱是其他，就不顯示下拉
                    if data.subs.count > 1 || (data.subs.count == 1 && data.subs.keys.first != "其他") {
                        for (subName, subData) in data.subs {
                            subStats.append(ProviderStats(
                                name: subName,
                                repeaterStr: self.formatBytes(subData.r),
                                macStr: self.formatBytes(subData.m),
                                othersStr: self.formatBytes(subData.o)
                            ))
                        }
                    }
                    
                    tempProviders.append(ProviderStats(
                        name: name,
                        repeaterStr: self.formatBytes(data.r),
                        macStr: self.formatBytes(data.m),
                        othersStr: self.formatBytes(data.o),
                        subStats: subStats.sorted(by: { $0.name > $1.name }) // 有線優先
                    ))
                }
                
                let sortedProviders = tempProviders.sorted { $0.name < $1.name }
                
                DispatchQueue.main.async {
                    self.totalRepeater = self.formatBytes(rTotal)
                    self.totalMac = self.formatBytes(mTotal)
                    self.totalOthers = self.formatBytes(oTotal)
                    self.allProviders = sortedProviders
                }
            }
        } catch {
            print("JSON parsing error: \(error)")
        }
    }
}
