# Security Policy

## System and scope

wattex is a single-file macOS menu bar app. It runs unprivileged, opens no network connections, takes no input other than its menu, and writes nothing except one user default and its login-item registration.

Its security-relevant surfaces are:

- Read-only calls to the AppleSMC user client with a hand-built 80-byte call struct (`main.swift`).
- Reads of the `AppleSmartBattery` registry entry and the IOKit power-source API.
- Login-item registration through `SMAppService`.
- `build.sh`, which compiles and ad-hoc signs the app.

## Trust boundaries and invariants

- SMC replies are untrusted input. The app checks the call result, the returned size, the key type and the key size, clamps the value to +-999 W, and treats anything else as a failed read.
- The app only reads SMC keys. It never writes them.
- The raw buffers are fixed at 80 bytes and every access is aligned and in bounds.
- The app must not gain network access, elevated privileges, extra entitlements or a helper tool without a documented reason.
- The login item registers once. Switching it off in Login Items must stay off.

## Reportable findings

Report a finding when it could realistically cause memory unsafety in the SMC handling, a write to SMC state, privilege escalation, an unexpected persistent login item, or a build-script path that runs unintended code.

An incorrect or stale power reading on an untested Mac model is a bug, not a vulnerability. Report it as an issue.

## Reporting route

Email `contact+wattex@magrathean.uk` with a minimal summary and the macOS version and Mac model. Do not publish vulnerability details in a public issue first.

## Version scope

Only the latest commit on `main` is maintained. No response-time commitment is published.
