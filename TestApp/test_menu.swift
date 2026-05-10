import SwiftUI

@main
struct TestApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("Popover Content")
        } label: {
            VStack(alignment: .trailing, spacing: -2) {
                HStack(spacing: 2) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text("10K")
                }
                HStack(spacing: 2) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("20K")
                }
            }
            .font(.system(size: 9, design: .monospaced))
        }
        .menuBarExtraStyle(.window)
    }
}
