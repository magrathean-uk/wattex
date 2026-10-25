import AppKit
import IOKit

// SMC key B0AP: signed battery power in mW (+charging, -discharging), refreshed ~1 Hz.
// The AppleSmartBattery registry is only refreshed every ~20 s, so it is not used.
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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Fixed width sized for the widest text ("888W+") and a monospaced font.
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
let button = item.button!
button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
button.title = "888W+"
item.length = button.fittingSize.width

let menu = NSMenu()
menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.menu = menu

var last = ""
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
}
timer.tolerance = 0.1
RunLoop.main.add(timer, forMode: .common)
timer.fire()
app.run()
