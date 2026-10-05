# Stage 6: v0.1 hardening

Oct 4, 2026 · Eidan Erlich · Status: built (shipped in 0.1.0)

## Goal

Before v0.1 ships, fix the backlog items a person would actually hit:
- an agent quietly undoing a person's lid mode;
- a 60-second wait for a notification that can't appear;
- wrong or misleading messages from `mooring`, `doctor` and Settings;
- a corrupt layouts file that blocks windows;
- blank VoiceOver rows;
- release script gaps.

There are no new features, and the version stays **0.1.0**, which hasn't been released.

## Decisions

| Area | Decision | Why |
| --- | --- | --- |
| **A person's lid is theirs** | A live lease, or menu session, whose lid mode a person set (it isn't recorded in `agentLid`) is **left untouched** when an agent's lid request on it is refused or must be asked. The agent gets `denied`, with the existing message plus " Your lease is unchanged." for a refusal, and the ask then proceeds without changing the lease. This applies to `lease acquire`, `anchor` and `on`.<br>Leases an agent created, or whose lid an agent got, keep today's rule: the agent's lease is held without lid.<br>The hook path is unchanged, since its `claude-…` leases are agent-owned. | Under Never, an agent re-acquiring your lid lease today takes your lid away. An agent shouldn't be able to downgrade what a person set. "The reply matches the outcome" still holds, because nothing changed. |
| **`on` with no flags** | Answers with the session only if it's live (`isLive(at:)`); otherwise it starts a fresh one, as if nothing were on. | A just-expired menu lease is up to 5 s stale. |
| **Re-acquire** | `grant` merges only with a **live** lease (`liveLease`), so an expired, not-yet-ticked lease is replaced, not revived. The "an agent's lease needs `--ttl` or `--watch-pid`" policy check reads the **request's** own watch, not the merged one. | Reviving an old watch and level surprises the caller. A raw wire client could skip the policy that the CLI enforces. |
| **Agent `on --until-off` over a timed session** | **Kept**, and documented in SPEC. An agent may already start an open-ended session without lid, the pill shows ∞, and the guardrails still apply. | It grants no new power. |
| **Asks that can't show** | `authorize()` is false unless notifications are authorized **and** alerts or banners are enabled (`alertSetting == .enabled`, `alertStyle != .none`). `post` reports failure. A failed post answers `unavailable` at once, for lid and window asks alike. | Today the agent waits 60 s for a notification that never appears. |
| **`mooring --version` and MCP `serverInfo`** | Read `CFBundleShortVersionString` from the enclosing `Mooring.app`'s `Contents/Info.plist`, found from the executable's real path (`…/Mooring.app/Contents/Helpers/mooring`). Fall back to `"unknown"` outside a bundle. | It says "0.2.0-dev" while the app is 0.1.0. |
| **"Didn't answer"** | `EAGAIN` on connect means "didn't answer". After the launch wait runs out, if a process with bundle id `dev.mooring.app` is running (an injected probe), the error is "didn't answer", not "isn't running". | A busy app isn't a missing one. |
| **CLI exits** | `printJSON` failing to encode exits 4, as `doctor` does. The launch deadline uses `ContinuousClock`. | Correct exit codes. |
| **npm-installed Claude** | A process named `node` whose first script argument ends in `/claude` or contains `/@anthropic-ai/claude-code/` counts as `claude`, both for the owner label (`ProcessTree.agentName`, `autoWatch`) and for agent detection (`AgentDetection`). The arguments are read with `sysctl(KERN_PROCARGS2)`. | Without this, an npm Claude is "node" and counts as a person, so lid approvals don't apply to it. |
| **`doctor`** | The Helper check is a pass ("not needed") when the helper isn't registered and nothing wants lid. When lid is believed disabled but sleep isn't actually disabled, the fix text reads "Turn lid mode off and on again". | No false failure for people who never use lid. The fix text is right in both directions. |
| **Settings → CLI** | A regular file at `~/.local/bin/mooring` shows "Not a link (Mooring won't replace it)", and Reinstall is disabled. | Today it says "Points to" its own path. |
| **Translocated or DMG copy** | When the bundle path contains `/AppTranslocation/` or starts with `/Volumes/`, Settings disables "Install command" and the MCP **Add** buttons, with "Move Mooring to Applications first". | Otherwise the configs point at a path that disappears. |
| **Layouts** | A `layouts.json` that won't decode is renamed to `layouts.corrupt-<unix time>.json` and treated as empty, with one log line. Ask text names apps by display name (bundle id → name through an injected resolver, falling back to the id). | A corrupt file shouldn't block windows, and asks should be readable. |
| **Socket `accept`** | On `EMFILE`/`ENFILE` the listener source is suspended and resumed after 100 ms. | Otherwise it busy-spins. |
| **VoiceOver** | Every hosted dropdown row has a non-empty title (the visible text) and a matching accessibility label. | Blank rows otherwise. |
| **Release script** | The tag check also asks `git ls-remote --tags origin`. A network failure there is a warning, not a pass. `make release ARGS=…` passes flags through. The appcast item gets `<sparkle:releaseNotesLink>https://github.com/EidanErlich/mooring/releases/tag/v<v></sparkle:releaseNotesLink>`. | These are stage 5 leftovers. |
| **Scripts and docs** | `cli-smoke.sh` gets an EXIT trap that kills its anchor and releases its leases. SPEC wording is fixed: 2.2's exit 2 is "held but paused by a guardrail", and the old "self-signed" wording becomes "your own certificate". The fixed BACKLOG items are removed. | Tidy up. |

## Not in this stage

- WindowKit `appBuild` dead code (vendored; a re-fetch restores it).
- Accessory apps in `win list`.
- MCP request concurrency.
- The remaining code-quality items in BACKLOG.

## Testing

Every behaviour above gets a unit test that fails first. The suite (`make test DERIVED=build/Unsigned XCODEBUILD_FLAGS="CODE_SIGNING_ALLOWED=NO"`) and `make lint` must pass. The installed app is checked with `cli-smoke.sh`, `doctor` and `--version`.
