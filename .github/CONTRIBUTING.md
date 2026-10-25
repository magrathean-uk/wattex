# Contributing to wattex

Start with a [bug report or feature request](https://github.com/magrathean-uk/wattex/issues). Say what the menu bar showed, what you expected, and which Mac and macOS version you used. Reporting a problem does not require a patch.

The source code is MIT-licensed (see [LICENSE](../LICENSE)). These are working conventions, not a separate contribution licence.

## Development

wattex is one Swift file with no dependencies. It needs Apple Silicon, macOS 13 or later and the Xcode command line tools.

```sh
./build.sh
open wattex.app
plutil -lint Info.plist
codesign --verify --strict wattex.app
git diff --check
gitleaks git --pre-commit --staged --redact --no-banner
```

`build.sh` writes `wattex.app` into the repository root. It is git-ignored. Quit a running copy from its menu bar item before rebuilding.

## Validate the changed behaviour

CI only compiles and inspects the bundle, because hosted runners have no battery or SMC power keys. Anything that changes behaviour needs a look at the running app on a real Mac.

- Layout: the item must not change width or shift the W or the sign as the number changes. Check one-, two- and three-digit values.
- Power: compare the number with `ioreg -rn AppleSmartBattery` (`Amperage` x `Voltage`) over a few seconds, allowing for the registry refreshing only about every 20 s.
- Icon: check discharging, charging, and plugged in under a load heavy enough to drain the battery. The bolt follows the charger, not the sign.
- Failures: a failed or mismatched SMC read must show `?W`, never `0W`.
- Login item: after a change to registration, check `sfltool dumpbtm` for a single enabled `dev.bolyki.wattex` record.

Keep changes small and the app dependency-free. Say which Macs and macOS versions a change was checked on, and which were not.
