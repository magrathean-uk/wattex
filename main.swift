import AppKit
import IOKit

// SMC key B0AP: signed battery power in mW (+charging, -discharging), refreshed ~1 Hz.
// The AppleSmartBattery registry is only refreshed every ~20 s, so it is not used for power.
// Macs without a battery have no B0AP; they fall back to PSTR (system total power, float watts).
var smc: io_connect_t = 0
IOServiceOpen(IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC")), mach_task_self_, 0, &smc)

let input = UnsafeMutableRawPointer.allocate(byteCount: 80, alignment: 8)
let output = UnsafeMutableRawPointer.allocate(byteCount: 80, alignment: 8)
input.initializeMemory(as: UInt8.self, repeating: 0, count: 80)
input.storeBytes(of: 4, toByteOffset: 28, as: UInt32.self)      // key data size
input.storeBytes(of: 5, toByteOffset: 42, as: UInt8.self)       // command: read bytes

/// Raw 4-byte value of an SMC key, or nil if the key does not exist.
func read(_ key: UInt32) -> UInt32? {
    input.storeBytes(of: key, as: UInt32.self)
    var size = 80
    guard IOConnectCallStructMethod(smc, 2, input, 80, output, &size) == kIOReturnSuccess,
          output.load(fromByteOffset: 40, as: UInt8.self) == 0 else { return nil }
    return output.load(fromByteOffset: 48, as: UInt32.self)
}

let b0ap: UInt32 = 0x4230_4150  // 'B0AP'
let pstr: UInt32 = 0x5053_5452  // 'PSTR'
let hasBattery = read(b0ap) != nil

func milliwatts() -> Int {
    if hasBattery { return Int(Int32(bitPattern: read(b0ap) ?? 0)) }
    let watts = Float(bitPattern: read(pstr) ?? 0)
    return watts.isFinite ? Int(watts * 1000) : 0
}

// CurrentCapacity is a percentage on Apple Silicon (MaxCapacity is 100).
let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))

func chargePercent() -> Int {
    let value = IORegistryEntryCreateCFProperty(battery, "CurrentCapacity" as CFString, kCFAllocatorDefault, 0)
    return (value?.takeRetainedValue() as? NSNumber)?.intValue ?? 0
}

// Template icon, always the same size so the item width never changes.
let iconSize = NSSize(width: 36, height: 18)
let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold) as CTFont

/// Battery filled to `step` * 5 % with the watts inside it (right-aligned) and a bolt on the left while on
/// power. A clear halo separates them from the fill, so they stay legible at any charge.
/// Without a battery it is a bare box with no fill or nub.
func icon(watts: Int, step: Int, onPower: Bool, hasBattery: Bool) -> NSImage {
    let image = NSImage(size: iconSize, flipped: false) { _ in
        let cg = NSGraphicsContext.current!.cgContext
        cg.setFillColor(NSColor.black.cgColor)
        cg.setStrokeColor(NSColor.black.cgColor)
        cg.setLineWidth(1.5)
        cg.addPath(CGPath(roundedRect: CGRect(x: 1.75, y: 2.75, width: 30.5, height: 12.5), cornerWidth: 4, cornerHeight: 4, transform: nil))
        cg.strokePath()
        if hasBattery {
            cg.addPath(CGPath(roundedRect: CGRect(x: 33.5, y: 6.5, width: 2, height: 5), cornerWidth: 1, cornerHeight: 1, transform: nil))
            cg.fillPath()
        }

        let fill = 28 * CGFloat(step) / 20
        if hasBattery && fill > 0 {
            let radius = min(2.5, fill / 2)
            cg.addPath(CGPath(roundedRect: CGRect(x: 3.5, y: 4.5, width: fill, height: 9), cornerWidth: radius, cornerHeight: radius, transform: nil))
            cg.fillPath()
        }
        let marks = CGMutablePath()
        var x: CGFloat = 30
        for character in String(watts).reversed() {
            var char = UniChar(character.asciiValue!), glyph = CGGlyph(), advance = CGSize.zero
            CTFontGetGlyphsForCharacters(digitFont, &char, &glyph, 1)
            CTFontGetAdvancesForGlyphs(digitFont, .horizontal, &glyph, &advance, 1)
            x -= advance.width
            if let path = CTFontCreatePathForGlyph(digitFont, glyph, nil) {
                marks.addPath(path, transform: CGAffineTransform(translationX: x, y: 9 - CTFontGetCapHeight(digitFont) / 2))
            }
        }
        if onPower {
            func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: 5 + u * 5.5, y: 4.75 + v * 8.5) }
            marks.addLines(between: [point(0.65, 1), point(0, 0.38), point(0.38, 0.38), point(0.28, 0),
                                     point(1, 0.62), point(0.62, 0.62)])
            marks.closeSubpath()
        }
        // Cut a thin clear halo around the digits and bolt out of the fill, then draw them solid.
        cg.setBlendMode(.clear)
        cg.setLineWidth(1.4)
        cg.setLineJoin(.round)
        cg.addPath(marks)
        cg.strokePath()
        cg.setBlendMode(.normal)
        cg.addPath(marks)
        cg.fillPath()
        return true
    }
    image.isTemplate = true
    return image
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Fixed width: the icon is constant-size and the title is always 2 monospaced characters ("W+", "W-", "W ").
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
let button = item.button!
button.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
button.imagePosition = .imageLeft
button.image = icon(watts: 888, step: 20, onPower: true, hasBattery: true)
button.title = "W+"
item.length = button.fittingSize.width

let menu = NSMenu()
menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.menu = menu

var last = ""
var tick = 0
var step = 0
let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
    let mW = milliwatts()
    let watts = Int((Double(abs(mW)) / 1000).rounded())
    let sign = watts == 0 || !hasBattery ? " " : (mW > 0 ? "+" : "-")
    // The charge only moves slowly, so it is re-read every 5 s.
    if hasBattery {
        if tick % 10 == 0 { step = min(20, max(0, Int((Double(chargePercent()) / 5).rounded()))) }
        tick += 1
    }
    let key = "\(watts)\(sign)\(step)"
    if key != last {
        last = key
        button.title = "W" + sign
        button.image = icon(watts: watts, step: step, onPower: sign != "-", hasBattery: hasBattery)
    }
}
timer.tolerance = 0.1
RunLoop.main.add(timer, forMode: .common)
timer.fire()
app.run()
