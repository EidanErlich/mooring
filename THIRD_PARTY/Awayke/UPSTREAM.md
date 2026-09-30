# Awayke

- Repo: https://github.com/daemonphantom/Awayke
- Commit: b50225198abb1c6e21c4d8da513bbd08fafa6a91 (2026-08-24)
- License: MIT (see LICENSE in this folder)
- Used for: lid-closed mode, the privileged helper, lid and battery monitors (stage 1)

## Files taken

| Upstream file | Mooring file |
| --- | --- |
| `AwaykeHelper/AwaykeHelperProtocol.swift` | `Helper/Shared/MooringHelperProtocol.swift` |
| `AwaykeHelper/main.swift` | `Helper/Sources/main.swift`, `Helper/Sources/HelperService.swift` |
| `AwaykeHelper/Info.plist` | `Helper/Info.template.plist` |
| `AwaykeHelper/daemonphantom.Awayke.Helper.plist` | `Helper/dev.mooring.helper.plist` |
| `Awayke/HelperManager.swift` | `App/Helper/HelperClient.swift` |
| `Awayke/DisplayWakeKeeper.swift` | `Packages/AwakeKit/Sources/AwakeKit/Assertions.swift` (stage 1b) |

## Modifications

- Renamed to Mooring identifiers: label, Mach service and binary `dev.mooring.helper`; associated bundle `dev.mooring.app`.
- Caller check enforced in code: the listener calls `setConnectionCodeSigningRequirement` with the requirement from the embedded `SMAuthorizedClients`. The requirement pins the signing certificate's SHA-1 instead of a Developer ID team, and is written at build time by `scripts/write-helper-requirement.sh`. Builds without a certificate get a placeholder, and the helper refuses every connection.
- The protocol gains `lidSleepDisabled` (reads `pmset -g`) and `version`; `setSleepDisabled` is renamed `setLidSleepDisabled`, and the `pmset` call moves to `Helper/Sources/PMSet.swift` with fixed argument arrays.
- `HelperClient`: `@MainActor`, Swift 6 strict concurrency, async calls guarded so each continuation resumes exactly once; a pending approval is not treated as a registration error.
- The osascript admin-password fallback (`Awayke/PowerManager.swift`) is not carried over.
- `Assertions.swift` (from `DisplayWakeKeeper`): merged with an idle-system-sleep assertion; both named "Mooring"; creates or releases each only when its desired state changes.
