<h1 align="center">wattex</h1>

<p align="center">A tiny macOS menu bar app that shows battery power in watts. Just the number.</p>

<p align="center">
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href=".github/CONTRIBUTING.md">Contributing</a> ·
  <a href=".github/SECURITY.md">Security</a>
</p>

## Overview

wattex shows how much power is flowing into or out of the battery, refreshed twice a second. The number sits next to a battery icon that fills in 5% steps, so the charge level is visible without the macOS battery indicator.

| Menu bar | Meaning |
| --- | --- |
| ` 12W+` | Battery charging at 12 W |
| ` 13W-` | Battery discharging at 13 W |
| `  0W ` | Battery idle |
| `  ?W ` | The reading failed |

The battery icon has a bolt cut out of it while a charger is connected, even when a heavy load is still draining the battery (shown as `W-`). The text is always five monospaced characters in a fixed-width item, so nothing shifts as the number changes.

On a Mac without a battery it shows total system power (`46W`, no sign) next to a bare bolt. That path is untested on real hardware.

## Requirements

Apple Silicon, macOS 13 or later, Xcode command line tools. Intel is rejected at compile time.

## Build and run

```sh
./build.sh
open wattex.app
```

The first launch registers wattex as a login item, so it starts after a restart. Switch it off in System Settings > General > Login Items. Quit from the menu bar item. Keep `wattex.app` where it was built, because the login item points at that path.

## How it works

- Power: SMC key `B0AP` (signed mW, refreshed about once a second), read through the AppleSMC user client every 0.5 s. No sudo.
- No battery: falls back to SMC key `PSTR` (system total power, float watts).
- Charge: `CurrentCapacity` from the `AppleSmartBattery` registry entry, re-read every 5 s.
- Charger: `IOPSGetProvidingPowerSourceType`.
- The `AppleSmartBattery` power fields are not used; they only refresh about every 20 s.

SMC keys are undocumented. They were checked on a Mac15,7 (M3 Pro) and may differ on other models; the app verifies each key's type and size and shows `?W` if it does not match.

## Licence

MIT. See [LICENSE](LICENSE).
