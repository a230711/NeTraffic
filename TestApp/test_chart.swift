import SwiftUI
import Charts
import Cocoa

struct ChartView: View {
    var body: some View {
        Chart {
            BarMark(x: .value("Day", "Mon"), y: .value("Sales", 10))
        }
        .frame(width: 200, height: 100)
    }
}
print("Chart imported successfully")
