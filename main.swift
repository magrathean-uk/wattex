import AppKit
import IOKit

// SMC key B0AP: signed battery power in mW (+charging, -discharging), refreshed ~1 Hz.
// The AppleSmartBattery registry is only refreshed every ~20 s, so it is not used.
var smc: io_connect_t = 0
IOServiceOpen(IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC")), mach_task_self_, 0, &smc)

let input = UnsafeMutableRawPointer.allocate(byteCount: 80, alignment: 8)
let output = UnsafeMutableRawPointer.allocate(byteCount: 80, alignment: 8)
input.initializeMemory(as: UInt8.self, repeating: 0, count: 80)
input.storeBytes(of: 0x4230_4150, as: UInt32.self)              // key 'B0AP'
input.storeBytes(of: 4, toByteOffset: 28, as: UInt32.self)      // key data size
input.storeBytes(of: 5, toByteOffset: 42, as: UInt8.self)       // command: read bytes

func milliwatts() -> Int {
    var size = 80
    guard IOConnectCallStructMethod(smc, 2, input, 80, output, &size) == kIOReturnSuccess else { return 0 }
    return Int(output.load(fromByteOffset: 48, as: Int32.self))
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
    let sign = watts == 0 ? " " : (mW > 0 ? "+" : "-")
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
