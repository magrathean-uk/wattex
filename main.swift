import AppKit
import IOKit
import IOKit.ps
import ServiceManagement

#if !arch(arm64)
#error("wattex relies on Apple Silicon SMC data (little-endian si32/flt keys, CurrentCapacity as a percentage); Intel is not supported")
#endif

// SMC key B0AP: signed battery power in mW (+charging, -discharging), refreshed ~1 Hz.
// The AppleSmartBattery registry is only refreshed every ~20 s, so it is not used for power.
// Macs without a battery have no B0AP; they fall back to PSTR (system total power, float watts).
var smc: io_connect_t = 0
let smcService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
let smcOK = smcService != 0 && IOServiceOpen(smcService, mach_task_self_, 0, &smc) == KERN_SUCCESS
IOObjectRelease(smcService)

let input = UnsafeMutableRawPointer.allocate(byteCount: 80, alignment: 8)
let output = UnsafeMutableRawPointer.allocate(byteCount: 80, alignment: 8)
input.initializeMemory(as: UInt8.self, repeating: 0, count: 80)
output.initializeMemory(as: UInt8.self, repeating: 0, count: 80)
input.storeBytes(of: 4, toByteOffset: 28, as: UInt32.self)      // key data size

/// One SMC call: command 9 = key info, 5 = read bytes. False if it fails or the key does not exist.
func call(_ key: UInt32, command: UInt8) -> Bool {
    input.storeBytes(of: key, as: UInt32.self)
    input.storeBytes(of: command, toByteOffset: 42, as: UInt8.self)
    var size = 80
    return IOConnectCallStructMethod(smc, 2, input, 80, output, &size) == kIOReturnSuccess
        && size == 80 && output.load(fromByteOffset: 40, as: UInt8.self) == 0
}

/// Raw 4-byte value of an SMC key, or nil if the call fails.
func read(_ key: UInt32) -> UInt32? {
    call(key, command: 5) ? output.load(fromByteOffset: 48, as: UInt32.self) : nil
}

/// True if the key exists and is 4 bytes of the given type (a shorter key would be read with zero padding).
func has(_ key: UInt32, type: UInt32) -> Bool {
    call(key, command: 9)
        && output.load(fromByteOffset: 28, as: UInt32.self) == 4
        && output.load(fromByteOffset: 32, as: UInt32.self) == type
}

let b0ap: UInt32 = 0x4230_4150  // 'B0AP'
let pstr: UInt32 = 0x5053_5452  // 'PSTR'
let si32: UInt32 = 0x7369_3332  // 'si32'
let flt: UInt32 = 0x666C_7420   // 'flt '

// CurrentCapacity is a percentage on Apple Silicon (MaxCapacity is 100).
let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
let hasBattery = smcOK && battery != 0 && has(b0ap, type: si32)
let hasPower = hasBattery || (smcOK && has(pstr, type: flt))

/// Signed milliwatts clamped to +-999 W (so garbage can neither trap nor overflow the 3-digit layout), or nil.
func milliwatts() -> Int? {
    guard hasPower, let raw = read(hasBattery ? b0ap : pstr) else { return nil }
    let value = hasBattery ? Double(Int32(bitPattern: raw)) : Double(Float(bitPattern: raw)) * 1000
    return value.isFinite ? Int(max(-999_000, min(999_000, value))) : nil
}

func chargePercent() -> Int? {
    let value = IORegistryEntryCreateCFProperty(battery, "CurrentCapacity" as CFString, kCFAllocatorDefault, 0)
    return (value?.takeRetainedValue() as? NSNumber)?.intValue
}

/// True while a charger is connected, whichever way the battery power is flowing.
func onACPower() -> Bool {
    IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String? == kIOPSACPowerValue
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

/// Battery glyph filled to `step` * 5 %; `charging` adds a bolt with a clear halo cut out of the battery.
func glyph(step: Int, charging: Bool) -> NSImage {
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
        if charging {
            func point(_ u: CGFloat, _ v: CGFloat) -> NSPoint { NSPoint(x: 8 + u * 7, y: 1.5 + v * 13) }
            let bolt = NSBezierPath()
            bolt.move(to: point(0.65, 1))
            bolt.line(to: point(0, 0.38))
            bolt.line(to: point(0.38, 0.38))
            bolt.line(to: point(0.28, 0))
            bolt.line(to: point(1, 0.62))
            bolt.line(to: point(0.62, 0.62))
            bolt.close()
            bolt.lineWidth = 2.4
            bolt.lineJoinStyle = .round
            NSGraphicsContext.current?.compositingOperation = .clear
            bolt.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            bolt.fill()
        }
        return true
    }
    image.isTemplate = true
    return image
}

// 0...20 discharging, then 21...41 on power (charging variant), one per 5 % step.
let glyphs = (0...20).map { glyph(step: $0, charging: false) } + (0...20).map { glyph(step: $0, charging: true) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Start at login: registered once, on the first successful launch. If it is later switched off in
// Login Items it stays off, because the flag is already set.
if !UserDefaults.standard.bool(forKey: "loginItemRegistered") {
    do {
        try SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: "loginItemRegistered")
    } catch {
        fputs("wattex: could not register login item: \(error)\n", stderr)
    }
}

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
var tick = 0
var step = 0
let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
    guard let mW = milliwatts() else { button.title = "  ?W "; return }
    let watts = Int((Double(abs(mW)) / 1000).rounded())
    let digits = String(watts)
    let sign = watts == 0 || !hasBattery ? " " : (mW > 0 ? "+" : "-")
    // Always 5 monospaced characters, so "W" and the sign never move; only the digits grow leftwards.
    let text = String(repeating: " ", count: max(0, 3 - digits.count)) + digits + "W" + sign
    if text != last {
        last = text
        button.title = text
    }
    // Battery in 5 % steps (bolt cut out of it while a charger is connected); bare bolt without a battery.
    // The charge only moves slowly, so it is re-read every 5 s.
    if hasBattery {
        if tick % 10 == 0, let percent = chargePercent() { step = min(20, max(0, Int((Double(percent) / 5).rounded()))) }
        tick += 1
    }
    let icon = hasBattery ? (onACPower() ? 21 : 0) + step : -1
    if icon != lastIcon {
        lastIcon = icon
        button.image = icon < 0 ? bolt : glyphs[icon]
    }
}
timer.tolerance = 0.1
RunLoop.main.add(timer, forMode: .common)
timer.fire()
app.run()
