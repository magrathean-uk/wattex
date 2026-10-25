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

// Template icons, all the same size so the item width never changes.
let iconSize = NSSize(width: 24, height: 16)

let bolt = NSImage(size: iconSize, flipped: false) { rect in
    let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)!
    let h: CGFloat = 12, w = symbol.size.width / symbol.size.height * h
    symbol.draw(in: NSRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h))
    return true
}
bolt.isTemplate = true

// 21 battery glyphs, one per 5 % step (0...100 %).
let batteries: [NSImage] = (0...20).map { step in
    let image = NSImage(size: iconSize, flipped: false) { _ in
        NSColor.black.set()
        let body = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 3.5, width: 18, height: 9), xRadius: 2.5, yRadius: 2.5)
        body.lineWidth = 1
        body.stroke()
        NSBezierPath(roundedRect: NSRect(x: 21.5, y: 6, width: 1.5, height: 4), xRadius: 0.75, yRadius: 0.75).fill()
        let fill = 15 * CGFloat(step) / 20
        if fill > 0 {
            let radius = min(1.5, fill / 2)
            NSBezierPath(roundedRect: NSRect(x: 4, y: 5, width: fill, height: 6), xRadius: radius, yRadius: radius).fill()
        }
        return true
    }
    image.isTemplate = true
    return image
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Fixed width sized for the widest text ("888W+") and a monospaced font.
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
let button = item.button!
button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
button.imagePosition = .imageLeft
button.image = bolt
button.title = "888W+"
item.length = button.fittingSize.width

let menu = NSMenu()
menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.menu = menu

var last = ""
var lastIcon = -2
let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
    let mW = milliwatts()
    let watts = Int((Double(abs(mW)) / 1000).rounded())
    let digits = String(watts)
    let sign = watts == 0 || !hasBattery ? " " : (mW > 0 ? "+" : "-")
    // Always 5 monospaced characters, so "W" and the sign never move; only the digits grow leftwards.
    let text = String(repeating: " ", count: max(0, 3 - digits.count)) + digits + "W" + sign
    if text != last {
        last = text
        button.title = text
    }
    // Bolt while running from power; battery in 5 % steps while it is being drained.
    let icon = sign == "-" ? min(20, max(0, Int((Double(chargePercent()) / 5).rounded()))) : -1
    if icon != lastIcon {
        lastIcon = icon
        button.image = icon < 0 ? bolt : batteries[icon]
    }
}
timer.tolerance = 0.1
RunLoop.main.add(timer, forMode: .common)
timer.fire()
app.run()
