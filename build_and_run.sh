#!/bin/bash
cd /Users/changkueichen/Program/Mac/WiFiBar

echo "Compiling Swift files into NeTraffic macOS App..."
swiftc NetworkStatsSrc/main.swift NetworkStatsSrc/NetworkMonitor.swift NetworkStatsSrc/StatsJSONReader.swift NetworkStatsSrc/ContentView.swift -o NeTraffic.app/Contents/MacOS/NeTraffic

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "Killing any existing instance..."
    killall NeTraffic 2>/dev/null
    
    # 移除舊的 SwiftBar 腳本，避免重複顯示
    rm -f /Users/changkueichen/Program/Mac/WiFiBar/wifi_menubar.*.sh
    
    echo "Launching NeTraffic..."
    ./NeTraffic.app/Contents/MacOS/NeTraffic > /dev/null 2>&1 &
else
    echo "❌ Build failed!"
fi
