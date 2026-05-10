import Cocoa

func createMenuBarImage(txString: String, rxString: String) -> NSImage {
    let width: CGFloat = 70
    let height: CGFloat = 22
    let image = NSImage(size: NSSize(width: width, height: height))
    
    image.lockFocus()
    
    // 上傳 (藍色圈圈，靠左)
    let txColor = NSColor.systemBlue
    txColor.setFill()
    let txRect = NSRect(x: 2, y: 12.5, width: 5, height: 5)
    let txPath = NSBezierPath(ovalIn: txRect)
    txPath.fill()
    
    // 下載 (紅色圈圈，靠左)
    let rxColor = NSColor.systemRed
    rxColor.setFill()
    let rxRect = NSRect(x: 2, y: 3.5, width: 5, height: 5)
    let rxPath = NSBezierPath(ovalIn: rxRect)
    rxPath.fill()
    
    // 繪製文字 (垂直置中校準)
    let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    
    let txAttrStr = NSAttributedString(string: txString, attributes: attrs)
    let rxAttrStr = NSAttributedString(string: rxString, attributes: attrs)
    
    let txSize = txAttrStr.size()
    let rxSize = rxAttrStr.size()
    
    // 流量數值完全靠右對齊
    let txX = width - txSize.width - 2
    let rxX = width - rxSize.width - 2
    
    txAttrStr.draw(at: NSPoint(x: txX, y: 11.5))
    rxAttrStr.draw(at: NSPoint(x: rxX, y: 1.5))
    
    image.unlockFocus()
    return image
}

let img = createMenuBarImage(txString: "  12 KB/s", rxString: " 1.2 MB/s")
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "test_image.png"))
    }
}
