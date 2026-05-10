import Foundation

struct ProviderStats: Identifiable {
    let id = UUID()
    let name: String
    let repeaterStr: String
    let macStr: String
    let othersStr: String
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
        print("Current Month: \(currentMonth)")
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let monthly = json["monthly"] as? [String: [String: Any]],
               let currentMonthData = monthly[currentMonth] as? [String: [String: Any]] {
                
                var rTotal: Int64 = 0
                var mTotal: Int64 = 0
                var oTotal: Int64 = 0
                
                var aggregatedStats: [String: (r: Int64, m: Int64, o: Int64)] = [:]
                
                let filter = (providerFilter == nil || providerFilter == "-" || providerFilter == "未偵測") ? nil : providerFilter
                print("Effective Filter: \(filter ?? "none")")
                
                for (key, statsDict) in currentMonthData {
                    
                    let repeater = (statsDict["repeater_total"] as? NSNumber)?.int64Value ?? 0
                    let mac = (statsDict["mac_total"] as? NSNumber)?.int64Value ?? 0
                    let others = (statsDict["others"] as? NSNumber)?.int64Value ?? 0
                    
                    // Grouping logic for allProviders
                    let baseName = key.replacingOccurrences(of: " 有線", with: "").replacingOccurrences(of: " 無線", with: "")
                    let current = aggregatedStats[baseName] ?? (r: 0, m: 0, o: 0)
                    aggregatedStats[baseName] = (r: current.r + repeater, m: current.m + mac, o: current.o + others)
                    
                    if let f = filter {
                        if key.contains(f) {
                            print("Match found: \(key) (R:\(repeater), M:\(mac), O:\(others))")
                            rTotal += repeater
                            mTotal += mac
                            oTotal += others
                        } else {
                            print("Skipping: \(key)")
                        }
                    } else {
                        rTotal += repeater
                        mTotal += mac
                        oTotal += others
                    }
                }
                
                var tempProviders: [ProviderStats] = []
                for (name, totals) in aggregatedStats {
                    tempProviders.append(ProviderStats(
                        name: name,
                        repeaterStr: self.formatBytes(totals.r),
                        macStr: self.formatBytes(totals.m),
                        othersStr: self.formatBytes(totals.o)
                    ))
                }
                let sortedProviders = tempProviders.sorted { $0.name < $1.name }
                
                DispatchQueue.main.async {
                    self.totalRepeater = self.formatBytes(rTotal)
                    self.totalMac = self.formatBytes(mTotal)
                    self.totalOthers = self.formatBytes(oTotal)
                    self.allProviders = sortedProviders
                    print("Updated UI: R=\(self.totalRepeater), M=\(self.totalMac), O=\(self.totalOthers)")
                }
            } else {
                print("Failed to find monthly data for \(currentMonth)")
            }
        } catch {
            print("JSON parsing error: \(error)")
        }
    }
}
