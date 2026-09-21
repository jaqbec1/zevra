# Verification

Local verification was performed with Bun 1.3.14 on macOS. This is implementation evidence, not evidence that recommendations are useful over two weeks.

## Automated checks

- Bun suite: 32 tests, covering policy, SQLite idempotency/rollback/retention, human precedence, HTTP authentication and ingestion, extraction, tracker transitions, Jev protocol/fallback, daily digests, subprocess timeout, and MCP.
- Strict TypeScript checking passed.
- Extension bundling passed.
- Prettier format checks passed.
- Real HTTP integration delivered a duplicate batch to a live loopback server without doubling attention.
- Real stdio MCP client initialized the server, listed all three tools, read summary/detail responses, and verified that an agent cannot overwrite a human correction.
- Synthetic demo generated a Markdown digest from fixture pages with no provider calls.
- Live HTTPS fetch of example.com succeeded through the DNS-validated, pinned-address request implementation. This smoke check caught and resolved Bun's requirement to honor the DNS lookup callback's `all` option.

Tests were added alongside the greenfield implementation. No pre-implementation red phase is claimed. There was no pre-existing test suite.

## Browser checks

An isolated Google Chrome for Testing 149 session loaded the unpacked extension. Chrome reported no manifest errors, runtime errors, or runtime warnings, and incognito access was disabled. The extension options page was inspected at 1280×900 and 390×844; controls were usable and the narrow layout had no horizontal overflow. Saving settings worked with a disposable test token and example.com allowlist.

A disposable collector received a real browser visit to example.com, with 9,766 ms of active time. Subsequent copy and selection events were each present once in SQLite, and the queue drained successfully. A visit to example.com with a synthetic token query parameter produced neither a queued event nor an additional stored page. The normal user browser profile and real browsing history were not used.

Full Arc Spaces/preview behavior, operating-system idle/lock, multiwindow focus, browser restart, prolonged offline recovery, and sleep/wake remain live acceptance checks. Reducer tests cover the state transitions but cannot establish those platform integrations.

## External integrations and product evidence

Jev's request and response contract is verified against current TypeSafe documentation and mocked responses. No live Jev API call was made with user credentials. The nightly agent's subprocess and validation contract is tested; no model-specific executable is configured. The fallback digest is usable without either integration.

Hister and Raindrop are not implemented. No scheduler is installed. No two-week usefulness results exist yet.

The idea assessment and plan checks were performed in this session using the supplied skill guidance and the repository's sequential-work instruction. They are not independent peer reviews. Plan contradictions resolved include uncertainty representation, durable event deduplication, exclusion order, return double-counting, and the absence of prose generation in Jev's Choice API.

### 2026-09-20 — exclusion-mode setup

- User selected exclusions instead of a mandatory allowed-site list.
- Added explicit `exclude` mode, decoded case-insensitive URL keyword matching, and a built-in Cloudflare dashboard exclusion. Legacy/missing mode remains allow-only; disabled collection still rejects all sites.
- Saved local collector policy for Gmail, ING, Cloudflare dashboards and `settings`, `login`, `account`. Token preserved; Jev remains disabled.
- Validation: 34 tests / 126 assertions passed; TypeScript and extension build passed. Regression cases cover subdomains, public Cloudflare docs/blogs, query/fragment keywords, and nested URL encoding.
- Loaded the built extension into Arc; extension manager confirmed Attention Log 0.1.0 enabled and “Extension loaded”. Collection has not been enabled or paired with the collector. User activity interrupted further browser setup, so no further UI actions were taken.
- Next: pair extension token and policy, start the collector, verify real delivery, then configure classification and daily digest scheduling.

### 2026-09-20 — Arc pairing completed

- Installed and started the collector as the current user's LaunchAgent. `launchctl` reports running; loopback health returns OK. Starts at login, with private runtime files and logs.
- Paired the existing Arc extension using the local token without printing it; saved exclusion mode, the agreed domains and keywords, and enabled capture. Reopened options confirms “Collection is enabled.”
- Actual Arc navigation to `https://example.com/?attention-log-test=setup` produced a persisted page and visit. Navigation to `/settings?attention-log-test=excluded` produced no matching page in SQLite. No synthetic event injection was used.
- Corrected the options page's stale default status text, which incorrectly said collection was off even when enabled. Typecheck and build passed.
- Jev remains disabled. Nightly digest scheduling and provider setup remain separate outstanding steps.

### 2026-09-20 — daily summary schedule

- Installed user LaunchAgent `com.attention-log.digest` for 03:15, with Europe/Warsaw process timezone and private runtime logs.
- Triggered the installed job through launchctl, not a separate foreground command; it completed and wrote `digests/2026-09-19.md` in local heuristic mode. That empty result is expected before the first collection day.
- Jev key is absent from the current environment; Jev remains disabled. Provider choice and local key entry are pending user input.

### 2026-09-20 — manual summaries requested

- User added the Jev key through the local script. Config now enables Jev and the collector health check succeeds.
- Unloaded the digest LaunchAgent and removed calendar/login/keepalive triggers from its retained plist. Automatic collector operation is unchanged; summary generation is manual.
- Current database has only a heuristic verdict and no pending classifier retry; real browsing-based Jev classification is not yet evidenced.
- Synthetic TypeSafe connection test (no browsing data) returned HTTP 200 and a valid choice response. This verifies the key and endpoint, not yet a real-page verdict.

### 2026-09-20 — README and development harness

- Rewrote README in Polish around setup, manual summaries, data flow and the distinction from Hister. Preserved detailed contracts in `docs/reference.md`; added repo-specific `AGENTS.md`.
- Added `bun run check` to run formatting, types, tests, extension build and synthetic demo in order, stopping on failure and isolating ATTENTION_HOME.
- Added read-only `bun run doctor` / `--json` with sanitized diagnostics and a two-second loopback health timeout. Tests cover missing/invalid config, no file creation, loopback-only probing and no secret/domain disclosure.
- New tests failed before the doctor implementation existed, then passed. Full check: 36 tests / 136 assertions, typecheck, format check, build and demo all passed. Live doctor returned only OK statuses.
- Scope review was performed inline under the session's sequential-work instruction; no independent reviewer or external review was used. The diagnostic does not verify extension delivery or provider credentials. No production configuration or schedule was changed by this task.

### 2026-09-20 — incremental manual digests and saved-page view

- Replaced the daily immutable result with appended run sections and persisted per-page input fingerprints. New/changed evidence is processed; unchanged data is skipped. The default CLI date is now today. Legacy digests are retained; the first upgraded run establishes fingerprints and can reconsider previously summarized pages.
- Inputs include current page metadata, attention metrics and verdict. Processing is bounded to 40 changed pages per call with a pending count; selection remains at most six items per run. Removed the former 500-page candidate ceiling for digest discovery. Prior sections remain historical, not a live replacement of older decisions.
- Added authenticated GET /pages with search, pagination, current-policy filtering and no-store responses. No excerpt is returned. The extension page renders untrusted titles/reasons as text and checks HTTP(S) before linking.
- Added the saved-page view, options link and toolbar action. Reloaded the installed Arc extension and restarted the collector. Arc showed 22 saved pages; searching for hister returned five. Desktop screenshot inspected. Mobile rendering was not exercised.
- New regression tests first failed on stale daily reuse and missing GET /pages. Final check passed: 40 tests, 156 assertions, formatting, typecheck, build and synthetic demo. Tests cover updated visits, changed verdicts, more than 500 pages, file-write recovery, authentication and exclusion filtering.
- Live manual digest processed 22 changed pages with pending=0; a second invocation returned reused=true and changed=0. Automatic summary scheduling remains disabled.

### 2026-09-20 — table/cards and Lucide icons

- Added a default semantic table with column headers, a saved table/cards preference, locally bundled Lucide icons, accessible metric labels, formatted durations, and expandable Polish classification descriptions. Human/agent reasons remain unchanged.
- Check passed: 40 tests, formatting, typecheck, extension build and synthetic demo. No backend or collection changes.
- Attempted live preview in Arc was interrupted by user activity. Separate browser preview was unavailable (in-app browser missing; Chrome creation timed out). Final visual/browser interaction verification of this change remains unconfirmed; no screenshot of the new table was obtained.

### 2026-09-20 — initial commit verification

- `bun run check` passed: formatting, TypeScript, 40 tests with 156 assertions, extension build, and synthetic demo. No live provider requests were made by this check.
- Authored saved-pages UI strings are English; table/cards and Lucide icons are built. Final visual acceptance and installed-extension reload remain unverified.
- Added `google.com` to this Mac's collector policy and restarted the service. The matching extension setting still needs saving; Arc UI automation was interrupted by user navigation. Runtime policy is outside Git.
- Confirmed the current Jev request has no personal profile or correction examples. README now states this limitation.

### 2026-09-21 — apply extension site rules without restarting the collector

- Root cause: options saved only browser storage; the collector retained its startup policy. Added authenticated POST /policy with strict validation, atomic private-file persistence, and immediate application to the shared policy object. Token, provider configuration, and summary settings are preserved.
- Saving options now records a revision and the background worker synchronizes the policy. The UI confirms collector acknowledgement. Offline/error responses remain pending, retry at most once per minute, and block event delivery until synchronized. An older response cannot acknowledge a newer save. Capture enable/disable remains local to the extension.
- In-flight extraction and classification recheck current exclusions before storing successful results. Already-sent network requests cannot be recalled. Manual config-file edits still require a restart; use extension options for automatic site-rule application.
- Regression test initially failed with HTTP 404 for the missing policy route. Final `bun run check` passed: formatting, TypeScript, 44 tests / 183 assertions, extension build, synthetic demo. Tests cover persistence, immediate ingestion/list filtering, failed persistence, authentication, invalid payloads, pending retries, acknowledgement races, and exclusion during classification. No live provider requests were made by these checks.
- Updated the installed collector with one service restart and reloaded the unpacked extension in Arc. Saved the user's existing form values and observed “Saved and applied to the collector. No restart needed.” Verified the persisted rules matched the form, collector PID stayed unchanged during save, all non-policy configuration was preserved, and config permissions remained 0600. Doctor passed. Visit capture and recommendation quality were not re-evaluated in this check.
- Scoped simplify and code review ran sequentially in the main thread under project instructions. Removed an unused import; no remaining findings in the fix scope. Unrelated `.deepsec/` material was excluded.

### 2026-09-21 — browse and open native saved materials

- Added native title/URL search, clear-search and no-results states, Open and Copy link buttons/context actions, and Load more in increments of 100 visits. Search covers stored history rather than only the currently visible list. Counts describe visits, not unique articles.
- The store reads bounded batches and applies the current URL policy before counting the visible limit. Open/copy recheck the same policy. No storage schema, capture timing, collection scope, provider, schedule, or CloudKit entitlement changed.
- Added a real temporary SQLite regression with 310 synthetic visits: 205 newer excluded entries followed by 105 eligible entries. It covers reaching older matches, case/diacritic-insensitive title search, URL search, whitespace trimming, excluded/no-match results, and limits. The test first failed to compile because the search/policy API did not yet exist, then passed after implementation.
- `sh macos/check.sh` passed: Swift formatting, all 10 native tests, and the local app build. The signed Cloud build also passed. `bun run check` passed: formatting, TypeScript, 44 tests / 183 assertions, extension build, and synthetic demo. No private database was used for tests and no AI provider was called.
- Verified the signed build in `--demo` mode: title and URL searches, one-result and no-result states, clearing the search, and the context menu. Copy link produced the exact synthetic URL when pasted into search; the previous clipboard contents were restored. Clicking the visible Open button created a browser tab at the expected example.com URL; the test tab was closed. The 860-by-700 window was visually inspected. Store tests cover pagination; the Load more button was not exercised in the three-record GUI demo.
- Simplification and correctness/adversarial diff passes ran sequentially in the main thread as required by project instructions. One shared viewing-policy helper replaced duplicate setup. No unresolved correctness finding remained. No independent peer review is claimed; the ce-code-review focused workflow could not supply its required independent reader under the project's main-thread-only constraint.
- Installed the signed Cloud build at `/Applications/Zevra.app` and restarted it. Its executable hash matches the tested Cloud build; its designated signing requirement and entitlements match the preceding installed app. The previous application bundle is retained at `~/Library/Application Support/Zevra Backups/20260921-061324/Zevra.app`. User databases and preferences were not migrated or reset.
- Limits: no new live capture, two-device sync, large-history performance, Intel execution, provider quality, or personalization verification is claimed. This change opens original URLs in the default browser; it does not cache content or import the older collector's history.
