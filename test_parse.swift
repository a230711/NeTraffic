import Foundation

let statsURL = URL(fileURLWithPath: "/Users/changkueichen/Program/Shell/ChangeWiFi/usage_stats.json")
guard let data = try? Data(contentsOf: statsURL) else {
    print("Failed to load")
    exit(1)
}

let currentMonth = "2026-05"

if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
   let monthly = json["monthly"] as? [String: [String: Any]],
   let currentMonthData = monthly[currentMonth] as? [String: [String: Any]] {
    
    let filters = ["星鏈", "中華電信", nil]
    
    for filter in filters {
        var rTotal: Int64 = 0
        var mTotal: Int64 = 0
        
        print("Testing filter: \(filter ?? "nil")")
        for (key, stats) in currentMonthData {
            guard let statsDict = stats as? [String: Any] else { continue }
            
            let repeater = (statsDict["repeater_total"] as? NSNumber)?.int64Value ?? 0
            let mac = (statsDict["mac_total"] as? NSNumber)?.int64Value ?? 0
            
            if let f = filter {
                if key.contains(f) {
                    rTotal += repeater
                    mTotal += mac
                }
            } else {
                rTotal += repeater
                mTotal += mac
            }
        }
        
        print("Result for \(filter ?? "nil"): R=\(rTotal), M=\(mTotal)")
    }
} else {
    print("Failed to parse JSON")
}
