import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var statsReader: StatsJSONReader
    
    @State private var isEditingLabels = false
    @State private var customDevice = ""
    @State private var customProvider = ""
    @State private var isShowingAllProviders = false
    @State private var expandedProviderID: String? = nil // 追蹤目前展開的單一項目 ID
    
    // Auto-refresh timer for JSON stats
    let refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    
    enum Tab {
        case overview, details
    }
    
    @State private var selectedTab: Tab = .overview
    @State private var detailsInactivityCount = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // --- 頂部導航區 ---
            Picker("", selection: $selectedTab) {
                Text("即時概覽").tag(Tab.overview)
                Text("流量明細").tag(Tab.details)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 12)
            
            // --- 內容區 ---
            VStack(spacing: 0) {
                if selectedTab == .overview {
                    overviewTab
                } else {
                    detailsTab
                }
            }
            .frame(minHeight: 460, alignment: .top)
            
            // --- 底部狀態列 ---
            Divider().padding(.horizontal, 24)
            
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(networkMonitor.rxSpeed > 0 || networkMonitor.txSpeed > 0 ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(networkMonitor.connectionMethod)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Text("退出程式")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    detailsInactivityCount = 0
                }
        )
        .onAppear {
            statsReader.refreshStats(providerFilter: networkMonitor.networkProvider)
        }
        .onChange(of: networkMonitor.networkProvider) { oldValue, newValue in
            statsReader.refreshStats(providerFilter: newValue)
        }
        .onChange(of: selectedTab) {
            detailsInactivityCount = 0
        }
        .onReceive(refreshTimer) { _ in
            statsReader.refreshStats(providerFilter: networkMonitor.networkProvider)
            
            // 流量明細 90 秒未操作自動切換回概覽 (30 * 3s = 90s)
            if selectedTab == .details {
                detailsInactivityCount += 1
                if detailsInactivityCount >= 30 {
                    selectedTab = .overview
                    detailsInactivityCount = 0
                }
            } else {
                detailsInactivityCount = 0
            }
        }
    }
    
    // --- 概覽分頁 ---
    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. 流量圖表區
            VStack(spacing: 8) {
                speedCard(title: "下載 (Download)", speed: networkMonitor.rxSpeed, history: networkMonitor.rxHistory, color: .red)
                speedCard(title: "上傳 (Upload)", speed: networkMonitor.txSpeed, history: networkMonitor.txHistory, color: .blue)
            }
            
            // 2. 連線資訊卡片
            VStack(alignment: .leading, spacing: 0) {
                cardHeader(title: "連線資訊", icon: "network")
                
                VStack(spacing: 8) {
                    proRow(label: "當前設備", value: networkMonitor.networkDevice, icon: "cpu")
                    proRow(label: "服務供應商", value: networkMonitor.networkProvider, icon: "antenna.radiowaves.left.and.right")
                }
                .padding(12)
                
                HStack {
                    Spacer()
                    Button(action: {
                        if !isEditingLabels {
                            customDevice = networkMonitor.networkDevice
                            customProvider = networkMonitor.networkProvider
                        }
                        isEditingLabels.toggle()
                    }) {
                        Label(isEditingLabels ? "取消" : "編輯標籤", systemImage: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
            
            // 編輯區 (展開式)
            if isEditingLabels {
                VStack(spacing: 8) {
                    TextField("自定義設備名稱", text: $customDevice)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    TextField("自定義供應商名稱", text: $customProvider)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    Button("確認儲存") {
                        networkMonitor.saveCustomMapping(device: customDevice, provider: customProvider)
                        isEditingLabels = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
                .padding(12)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(10)
            }
            
            // 3. 本月統計卡片
            VStack(alignment: .leading, spacing: 0) {
                cardHeader(title: "本月流量累計", icon: "chart.pie.fill")
                
                VStack(spacing: 10) {
                    proStatRow(label: "中繼器 (Repeater)", value: statsReader.totalRepeater, color: .primary)
                    proStatRow(label: "本機 (Mac)", value: statsReader.totalMac, color: .primary)
                    Divider().opacity(0.3)
                    proStatRow(label: "其他 (Others)", value: statsReader.totalOthers, color: .secondary)
                }
                .padding(12)
            }
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
    
    // --- 明細分頁 ---
    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("所有供應商流量明細", systemImage: "list.bullet.indent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(statsReader.allProviders) { provider in
                        VStack(spacing: 0) {
                            // 主項目
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if expandedProviderID == provider.id {
                                        expandedProviderID = nil
                                    } else {
                                        expandedProviderID = provider.id
                                    }
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(provider.name)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.primary)
                                        
                                        HStack(spacing: 12) {
                                            miniStat(label: "中繼", value: provider.repeaterStr)
                                            miniStat(label: "Mac", value: provider.macStr)
                                            miniStat(label: "其他", value: provider.othersStr)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if !provider.subStats.isEmpty {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.secondary)
                                            .rotationEffect(.degrees(expandedProviderID == provider.id ? 90 : 0))
                                    }
                                }
                                .padding(12)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            
                            // 子項目 (下拉內容)
                            if expandedProviderID == provider.id && !provider.subStats.isEmpty {
                                VStack(spacing: 1) {
                                    ForEach(provider.subStats) { sub in
                                        HStack {
                                            Text(sub.name)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.secondary)
                                                .frame(width: 60, alignment: .leading)
                                            
                                            Spacer()
                                            
                                            HStack(spacing: 16) {
                                                miniStat(label: "中繼", value: sub.repeaterStr)
                                                miniStat(label: "Mac", value: sub.macStr)
                                                miniStat(label: "其他", value: sub.othersStr)
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .background(Color.primary.opacity(0.02))
                                    }
                                }
                                .padding(.bottom, 4)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
    
    // --- UI 元件庫 ---
    
    @ViewBuilder
    private func speedCard(title: String, speed: UInt64, history: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(color)
                Spacer()
                Text(formatSpeedText(speed))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            
            Chart {
                ForEach(Array(history.enumerated()), id: \.offset) { index, value in
                    AreaMark(
                        x: .value("Time", index),
                        y: .value("Speed", value)
                    )
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    
                    LineMark(
                        x: .value("Time", index),
                        y: .value("Speed", value)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .interpolationMethod(.monotone)
            }
            .frame(height: 38)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
        .padding(10)
        .background(color.opacity(0.04))
        .cornerRadius(12)
    }
    
    private func cardHeader(title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .foregroundColor(.secondary)
    }
    
    private func proRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }
    
    private func proStatRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }
    
    private func miniStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
    }
    
    private func formatSpeedText(_ bytesPerSec: UInt64) -> String {
        let kbps = Double(bytesPerSec) / 1024.0
        if kbps >= 1000 {
            return String(format: "%.1f MB/s", kbps / 1024.0)
        } else {
            return String(format: "%.0f KB/s", kbps)
        }
    }
}
