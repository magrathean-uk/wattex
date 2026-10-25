# Wattex project context

Wattex is a single-file Swift menu bar app for Apple Silicon Macs (macOS 13 or later). It shows battery power in watts, for example `12W+` while charging and `13W-` while discharging. It has no dependencies, no network access and needs no elevated privileges.

## Code and product map

- `main.swift` is the whole app: AppleSMC access, the power, charge and charger reads, the icon drawing, the status item, the 0.5 s timer and login-item registration.
- `Info.plist` sets `LSUIElement` (no Dock icon), `LSMinimumSystemVersion` 13.0 and bundle id `dev.bolyki.wattex`.
- `build.sh` compiles and ad-hoc signs `wattex.app` in the repository root. The bundle is git-ignored, and the login item points at it, so do not move or delete it casually.
- `.github/workflows/ci.yml` only compiles and inspects the bundle. Hosted runners have no battery or SMC to read, so the app is never run there.

## Data sources and invariants

- Power is SMC key `B0AP`: signed mW, positive while charging, refreshed about once a second. It is a little-endian `si32`; the app checks the key type and size before using it.
- With no battery it falls back to SMC key `PSTR` (float watts, system total) and shows no sign.
- Charge is `CurrentCapacity` on the `AppleSmartBattery` registry entry, a percentage on Apple Silicon. It is re-read every 5 s.
- The charger state comes from `IOPSGetProvidingPowerSourceType`. The bolt follows the charger, not the sign of the battery power: a heavy load on a weak charger drains the battery while plugged in.
- Do not read power from the `AppleSmartBattery` registry. Those fields refresh only about every 20 s.
- The title is always 5 monospaced characters and the item has a fixed length measured from `888W+`. All icons are 24x16 template images. Keep both, or the menu bar item shifts.
- Power is clamped to +-999 W. A failed read shows `?W`, never `0W`.
- The build is arm64 only and needs `-swift-version 5`. Both are enforced (`#error` and `build.sh`).
- The login item registers once, guarded by the `loginItemRegistered` user default, so switching it off in Login Items sticks.

## Command references

```sh
./build.sh
open wattex.app
plutil -lint Info.plist
codesign --verify --strict wattex.app
vtool -show-build wattex.app/Contents/MacOS/wattex | grep minos
git diff --check
gitleaks git --pre-commit --staged --redact --no-banner
sfltool dumpbtm | grep -B8 -A8 'dev.bolyki.wattex$'
```

`sfltool dumpbtm` shows the login-item record. The menu bar text and icons can only be checked by looking at the running app.

## Verification gaps

Tested on one Mac (Mac15,7, M3 Pro). Not tested: desktop Macs (the `PSTR` fallback), other chip generations, macOS 13 to 26, sleep and wake, and a reboot with the login item enabled.
