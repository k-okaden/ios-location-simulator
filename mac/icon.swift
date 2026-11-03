// アプリアイコン（青地に白い位置ピン）を 1024px の PNG として書き出す
import Cocoa

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.27, green: 0.56, blue: 1, alpha: 1),
           ending: NSColor(red: 0.12, green: 0.33, blue: 0.85, alpha: 1))!.draw(in: bg, angle: -90)

let pin = NSBezierPath()
let cx: CGFloat = 512, cy: CGFloat = 590, r: CGFloat = 190
pin.move(to: NSPoint(x: cx, y: 230))
pin.curve(to: NSPoint(x: cx - r, y: cy), controlPoint1: NSPoint(x: cx - 60, y: 330), controlPoint2: NSPoint(x: cx - r, y: 450))
pin.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: 180, endAngle: 0, clockwise: true)
pin.curve(to: NSPoint(x: cx, y: 230), controlPoint1: NSPoint(x: cx + r, y: 450), controlPoint2: NSPoint(x: cx + 60, y: 330))
NSColor.white.setFill()
pin.fill()
NSColor(red: 0.12, green: 0.33, blue: 0.85, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: cx - 75, y: cy - 75, width: 150, height: 150)).fill()
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
