import AppKit

guard CommandLine.arguments.count == 3 else {
  fputs("Usage: render_store_feature_graphic <input.png> <output.png>\n", stderr)
  exit(64)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let input = NSImage(contentsOf: inputURL) else {
  fputs("Could not read \(inputURL.path)\n", stderr)
  exit(66)
}

let size = NSSize(width: 1024, height: 500)
guard let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: Int(size.width),
  pixelsHigh: Int(size.height),
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  fputs("Could not create output bitmap\n", stderr)
  exit(70)
}

let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

input.draw(
  in: NSRect(origin: .zero, size: size),
  from: NSRect(origin: .zero, size: input.size),
  operation: .sourceOver,
  fraction: 1
)

func draw(_ text: String, at point: NSPoint, font: NSFont, color: NSColor,
          tracking: CGFloat = 0) {
  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = .left
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
  shadow.shadowBlurRadius = 4
  shadow.shadowOffset = NSSize(width: 0, height: -1)
  let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: color,
    .paragraphStyle: paragraph,
    .shadow: shadow,
    .kern: tracking,
  ]
  (text as NSString).draw(at: point, withAttributes: attributes)
}

let gold = NSColor(calibratedRed: 0.86, green: 0.69, blue: 0.22, alpha: 1)
let cream = NSColor(calibratedWhite: 0.97, alpha: 1)
let muted = NSColor(calibratedWhite: 0.9, alpha: 0.84)

draw(
  "HI-LO",
  at: NSPoint(x: 58, y: 324),
  font: NSFont.systemFont(ofSize: 17, weight: .bold),
  color: gold,
  tracking: 4
)
draw(
  "BLACKJACK",
  at: NSPoint(x: 56, y: 257),
  font: NSFont.systemFont(ofSize: 45, weight: .black),
  color: cream,
  tracking: 1.2
)
draw(
  "TRAINER",
  at: NSPoint(x: 59, y: 219),
  font: NSFont.systemFont(ofSize: 24, weight: .bold),
  color: gold,
  tracking: 6
)
draw(
  "COUNT. PRACTICE. PLAY TOGETHER.",
  at: NSPoint(x: 60, y: 172),
  font: NSFont.systemFont(ofSize: 11, weight: .semibold),
  color: muted,
  tracking: 1.3
)

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fputs("Could not encode PNG\n", stderr)
  exit(70)
}
try png.write(to: outputURL)
