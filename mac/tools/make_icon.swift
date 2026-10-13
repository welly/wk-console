// Renders WK Console's app icon to a 1024 px PNG: swift tools/make_icon.swift out.png
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Rounded square with the standard macOS icon margin, deep blue to teal.
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [
    NSColor(red: 0.07, green: 0.20, blue: 0.42, alpha: 1),
    NSColor(red: 0.05, green: 0.52, blue: 0.60, alpha: 1),
])!.draw(in: shape, angle: -60)

// Radio waves symbol, in white.
let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .medium)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 + 70, width: s.width, height: s.height))
}

// "WK" underneath.
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 150, weight: .heavy),
    .foregroundColor: NSColor.white.withAlphaComponent(0.92),
    .kern: 12,
]
let label = NSAttributedString(string: "WK", attributes: attrs)
let ls = label.size()
label.draw(at: NSPoint(x: (size - ls.width) / 2, y: 190))

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
