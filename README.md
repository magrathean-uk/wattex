# wattex

Menu bar battery power in watts. `12W+` is the battery charging at 12 W, `13W-` is it discharging at 13 W. The icon is a battery filled in 5% steps, with a bolt cut out of it while a charger is connected (even if the battery is still being drained by a heavy load, which shows as `W-`).

On a Mac without a battery it shows total system power (`46W`, no sign) next to a bare bolt. That path is untested on real hardware.

## Requirements

Apple Silicon, macOS 13 or later, Xcode command line tools. Intel is rejected at compile time.

## Build and run

```sh
./build.sh
open wattex.app
```

The first launch registers the app as a login item, so it starts after a restart. Switch it off in System Settings > General > Login Items. Quit from the menu bar item.

## How it works

- Power: SMC key `B0AP` (signed mW, refreshed about once a second), read through the AppleSMC user client every 0.5 s. No sudo.
- No battery: falls back to SMC key `PSTR` (system total power, float watts).
- Charge: `CurrentCapacity` from the `AppleSmartBattery` registry entry, re-read every 5 s.
- The `AppleSmartBattery` power fields are not used; they only refresh about every 20 s.
