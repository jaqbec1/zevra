# Zevra — native macOS prototype

The user selected Swift and SwiftUI on 2026-09-21. The first slice is a menu-bar app that identifies an eligible active Arc document, estimates active time, persists observations locally, and has a CloudKit-enabled build for a two-Mac trial. This is separate from the existing Bun collector and browser extension. Neither the original specification nor the installed collector is changed.

The app is now named **Zevra** and is installed at `/Applications/Zevra.app`. It uses a regular macOS application window, with Dock and Command-Tab access, while retaining its menu-bar controls. Losing focus does not close the window. Existing technical identifiers (`com.jamatyka.AttentionLog`, the CloudKit container, and the local storage directory) remain stable across the display-name change.

## Browse saved materials

The **Saved materials** view searches titles and URLs across the native app's stored history, including visits older than the first 100 shown. Search ignores letter case and diacritics. **Load more** shows another 100 matching visits; **Clear search** restores the recent list. Each row remains one visit, so repeated visits to an article or video appear separately.

Choose **Open** to open the original article or video in the default browser, or **Copy link** to copy its full saved URL. Both actions are also available in the row's context menu. Zevra does not store offline copies or play videos inside its window. Site exclusions still apply to searches and to opening or copying a link, even while capture is paused.

This view uses the native observation store. It does not import the older Bun collector history or a personal profile, and does not call Jev.

## Run locally

### 0.1.1 preview verification

The apparent background timer was the unlabeled SwiftUI relative `lastSeenAt` date, which kept advancing independently of capture. Two read-only checks of the public example.com test visit returned the same 24.6796 active seconds while Arc was not foreground. The UI now labels **Active time** separately and renders **Last seen** as a fixed date and time. Capture accounting and stored records were not changed.

The settings disclosure uses a custom header with its focus effect disabled only on that header. Mouse collapse and keyboard Tab/Space expansion were checked in the installed app; the clipped blue outline is gone and domain fields keep their normal focus behavior. These presentation defects have no Swift package test seam, so verification used the actual window rather than a test of duplicated formatting logic.

All nine native tests, Swift formatting, the local build, the signed Cloud build, and the universal Release build passed. The installed Cloud app retained Accessibility permission. Targeted manual review and reuse/quality/efficiency review of the changed files found no further changes needed. Intel execution, Gatekeeper first launch on another Mac, notarization, and cross-device iCloud sync were not verified.

`sh macos/package-preview.sh` creates an ad-hoc-signed universal ZIP and SHA-256 checksum in `macos/build/artifacts/`. It deliberately uses Release with iCloud disabled and no development provisioning profile. The public preview is unnotarized; Cloud distribution requires a separate distribution-signing/provisioning setup. Do not replace an iCloud development installation with the local-only preview if you want to keep syncing.

Requires Xcode with the macOS SDK, Swift 6, and macOS 14 or later. The Xcode project is checked in; XcodeGen is needed only after editing `macos/project.yml`.

```sh
sh macos/check.sh
open macos/build/Build/Products/Debug/Zevra.app --args --demo
```

Demo mode uses an in-memory store and fictional observations from two devices. It does not access Accessibility, register a login item, connect to CloudKit, read existing data, or save preferences. Quit the demo before starting the ordinary app:

```sh
open macos/build/Build/Products/Debug/Zevra.app
```

For a stable trial installation, build with your own signing identity and copy the app into Applications before granting Accessibility or enabling launch at login. Development rebuilds with ad-hoc signing can invalidate an earlier Accessibility approval. The default Debug build works locally without an Apple account; it has no iCloud entitlements.

1. Optionally save allowed domains to limit capture, such as `example.com, wikipedia.org`. With Allowed domains empty, all otherwise eligible sites are included. Both domain fields accept commas, spaces, or newlines and include subdomains. Exclusions take precedence; invalid entries prevent saving either list. Rules apply to the native prototype only.
2. Read the Accessibility explanation and choose **Grant access**. macOS grants broad access to application interfaces; this prototype reads only Arc document identities. It does not request Screen Recording, microphone access, or Full Disk Access.
3. Enable capture. Spend several seconds on one eligible page in a normal Arc window. Check the saved observation and duration.
4. Optionally enable **Launch at login**. Closing the window leaves the menu-bar app running; Quit exits it. Verify launch at the next real login separately.

## What is collected

The native prototype records a generated visit ID, an installation-specific device ID, normalized URL, title, start and last-seen timestamps, and cumulative estimated active seconds. The local store is in `~/Library/Application Support/com.jamatyka.AttentionLog/observations.sqlite`. It is not the existing collector database and is not a file in iCloud Drive.

Capture requires an explicit per-installation opt-in, a URL permitted by the saved rules, Accessibility permission, an active Arc window, one unambiguous document in the accessibility tree, and recent input. URL rules run before the title is read or an observation is stored. Sensitive built-in domains, authentication-like routes and parameters, credentials, explicit ports, IP literals, and decoded `settings`, `login`, and `account` matches are rejected. This is a conservative subset of the original collector policy, not a complete detector of private pages or private browsing windows. No page text, selected text, screenshots, audio, or AI requests are involved.

Two-second samples credit only intervals bracketed by the same eligible URL. A missing/ambiguous document, application switch, idle period of 60 seconds, sleep/display/session transition, or a sample gap over five seconds resets the interval. This intentionally undercounts transitions. Scroll, copy and selection measurements from the extension are not reproduced. Arc split views or an incomplete accessibility tree are skipped. Single-page Arc capture has been verified live; the remaining acceptance cases below still need testing.

Each Mac writes distinct visit IDs; a cumulative checkpoint replaces the earlier checkpoint for that visit instead of adding its time again. Device totals may overlap in wall-clock time when two Macs are used simultaneously. The prototype displays individual observations rather than claiming deduplicated person-time.

## iCloud build

CloudKit uses the private database of the signed-in iCloud user. The native app's Core Data store has an explicit CloudKit configuration only in the **Cloud** build. There is no application server to run. CloudKit sync is asynchronous; the UI reports the last setup/import/export event, not proof that all devices have identical data.

Create the gitignored `macos/Signing.local.xcconfig` with your personal team:

```text
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

Sign into that Apple Developer account in **Xcode → Settings → Apple Accounts**. The team must support CloudKit. The project uses bundle ID `com.jamatyka.AttentionLog` and container `iCloud.com.jamatyka.AttentionLog`; if those names are unavailable for the team, change both consistently in `project.yml` and regenerate the project.

```sh
xcodebuild -project macos/AttentionLog.xcodeproj \
  -scheme AttentionLog-Cloud -configuration Cloud \
  -derivedDataPath macos/build-cloud -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration build
```

The cloud-enabled build synchronizes the native observation store, including previously collected local observations. It does not upload or migrate the old Bun database. Use the same app identity, CloudKit container/environment, and iCloud account on both Macs. Never copy a live SQLite store between machines or move it into iCloud Drive. Do not reset the local store to resolve an iCloud error.

For the first signed development build, initialize the development schema through Core Data's CloudKit setup and check setup/import/export events. Production schema deployment and distribution signing are separate release steps. Automatic updates, a release feed, shared capture rules, migration of old history, summaries, and retention/deletion UI are outside this first slice. Observations currently remain until the prototype's data is explicitly removed; do not use this build for unattended long-term capture yet.

## Acceptance on two Macs

Use a public test page and explicit rules on each Mac. Grant Accessibility separately; macOS permissions and capture opt-in must not sync.

1. Capture a short observation on Mac A and confirm an iCloud export completes.
2. Open Mac B with the same iCloud account and rules. Confirm the same visit appears once, attributed to another Mac, after import.
3. Disconnect Mac B, collect another visit, reconnect and confirm it appears once on Mac A. Reopening either app must not increase recorded time.
4. Verify switching applications, idle time, sleep, screen locking, fast-user switching, and Arc split views do not accumulate time. If screen-lock behavior is not confirmed, leave capture paused when locking.
5. Test permission revocation, unavailable iCloud, and denied login-item approval. Errors must be visible; local observations must survive.

## Verification — 2026-09-21

- Tests were introduced before core implementation and first failed because the new policy/tracker/store types did not exist.
- Nine Swift tests pass: optional allowlists with exclusion precedence; comma/whitespace parsing and invalid-entry detection; disabled defaults; exclusions before normalization; idle/switch/sleep gaps; persistent SQLite reopening and idempotent checkpoints; independent display/session gates; an integrated policy → tracker → store flow with two synthetic devices; and storage initialization failure preserving existing bytes.
- Local Debug application builds with Xcode. Xcode emits its standard App Intents metadata warning because this app does not use App Intents.
- The actual app window was inspected in demo mode and in the empty first-run state. The initial build required saved allowed domains; this requirement was subsequently removed at the user’s request. Accessibility was not granted during verification.
- Existing `bun run check` passes, including 44 tests, formatting, TypeScript, extension build, and the synthetic demo. No live provider calls were made.
- The first cloud signing attempt was blocked by a missing personal account in Xcode. After the user signed in, automatic provisioning registered this Mac and produced a valid Mac App Development profile. The installed app's signature was verified against the requested personal team. No company identity was used.
- The initial signed build failed CloudKit setup with `CKErrorDomain Code=5`. Its signed entitlements lacked `com.apple.developer.icloud-container-environment`, although the provisioning profile permitted both environments. Adding the explicit `Development` entitlement and rebuilding resolved setup; the installed Zevra then reported `iCloud · Upload completed`. Capture remained paused and the displayed observation count was zero. This verifies CloudKit setup/export activity, not browsing-history delivery or two-device synchronization.
- Renamed the installed app to Zevra and changed `LSUIElement` from true to false so its existing window participates in normal Dock/Command-Tab app switching. UI inspection after switching focus still found the Zevra window. Launch-at-login registration was moved from the previous build path to the installed Zevra app, and the UI confirmed it enabled. A real login/relaunch test and two-device synchronization remain unverified. Live Arc delivery was subsequently verified as described below.

Implementation and review run in the main thread under the project's sequential-work instruction. No independent peer review is claimed.

## Capture troubleshooting — 2026-09-21

A saved Accessibility toggle did not initially reach the running signed app. TCC logs showed a code requirement for an earlier binary hash and a denied composed authorization. Resetting only PostEvent did not help; resetting Accessibility for `com.jamatyka.AttentionLog` and having the user grant it again changed the app to `Accessibility enabled`. A subsequent signed app update retained the grant.

A separate idle-detection bug queried `CGEventType.null`, which is a specific event type, instead of `kCGAnyInputEventType` (`UInt32.max`). A live diagnostic returned approximately 144291 seconds for null events and 0.005 seconds for any input. The app now queries any input, and missing Accessibility permission takes priority over idle status. Nine core tests and both local and signed Cloud builds passed; the installed app advanced to `Waiting for Arc`.

The next live Arc test reached `Arc document lookup incomplete`: the whole-window traversal exhausted its node budget on sidebar tabs/spaces. The reader now starts at the focused window's direct `AXSplitGroup` content containers, preserving its bounded traversal and exactly-one-document requirement. It does not traverse sidebar tab titles. Nine core tests and the signed build passed after the change.

Live capture was subsequently confirmed after the user kept example.com in foreground Arc: a read-only aggregate query found one saved example.com observation with approximately 24.68 active seconds. This verifies foreground Arc capture through local persistence for the public test page; cross-device synchronization remains unverified.
