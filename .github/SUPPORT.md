# wattex support

For setup and everyday use, start with the [README](../README.md). Report reproducible bugs and feature requests through [GitHub issues](https://github.com/magrathean-uk/wattex/issues). The contact is [contact+wattex@magrathean.uk](mailto:contact+wattex@magrathean.uk).

## Include enough detail to reproduce

Give the macOS version, the Mac model (`sysctl -n hw.model`), what the menu bar showed and what you expected. Add the output of `pmset -g batt` and whether a charger was connected.

## Common checks

- The number is the battery's power flow, not the whole system's draw. A plugged-in laptop under a light load can show `0W`.
- `W-` while plugged in means the load exceeds what the charger supplies and the battery is covering the gap.
- `?W` means an SMC read failed or the key did not match the expected type. This is expected on Intel Macs, which are not supported.
- The battery icon steps change every 5% and the charge is re-read every 5 s.
- If it does not start after a restart, check System Settings > General > Login Items. Keep `wattex.app` where it was built.
