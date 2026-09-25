# Zevra — native macOS prototype

The user selected Swift and SwiftUI on 2026-09-21. The first slice is a menu-bar app that identifies an eligible active Arc document, estimates active time, persists observations locally, and has a CloudKit-enabled build for a two-Mac trial. This is separate from the existing Bun collector and browser extension. Neither the original specification nor the installed collector is changed.

The app is now named **Zevra** and is installed at `/Applications/Zevra.app`. It uses a regular macOS application window, with Dock and Command-Tab access, while retaining its menu-bar controls. Losing focus does not close the window. Existing technical identifiers (`com.jamatyka.AttentionLog`, the CloudKit container, and the local storage directory) remain stable across the display-name change.

## Browse saved materials

The **Saved materials** view searches titles and URLs across the native app's stored history, including visits older than the first 100 shown. Search ignores letter case and diacritics. **Load more** shows another 100 matching visits; **Clear search** restores the recent list. Each row remains one visit, so repeated visits to an article or video appear separately.

Choose **Open** to open the original article or video in the default browser, or **Copy link** to copy its full saved URL. Both actions are also available in the row's context menu. Zevra does not store offline copies or play videos inside its window. Site exclusions still apply to searches and to opening or copying a link, even while capture is paused.

This view uses the native observation store. It does not import the older Bun collector history or a personal profile. Jev suggestions are a separate, optional native feature.

## Jev suggestions (0.2.0)

In **Settings → Jev suggestions**, save a TypeSafe API key to this Mac's Keychain, then explicitly enable classification. Saving the key alone does not enable it. Capture and Jev have separate switches. Removing the key turns Jev off; neither action deletes observations or human corrections. The key is not printed, placed in the repository, or synced with CloudKit.

After an eligible HTTPS page accumulates 10 active seconds across saved visits, Zevra fetches public HTML without Arc cookies or redirects. If it extracts at least 80 words, it sends the title, domain, and up to 2,000 characters of page text to TypeSafe's `jev-latest` Choice endpoint. This occurs while the page can still be open; switching away and closing are not triggers. It does not backfill older visits when Jev is enabled. Failed fetches and provider errors leave the visit intact and retry at most three times, at least five minutes apart. Exclusions are checked before fetching and before submitting. A result is reused for unchanged evidence; active pages may be rechecked after an hour for content changes.

The row labels the provider suggestion and shows **Needs review** below 0.6 confidence. The ellipsis menu lets the user choose **Read deeper**, **Keep as reference**, or **No obvious follow-up**; a human choice takes precedence permanently. Suggestions and corrections live in a separate local `classifications.json` file with owner-only permissions, outside the CloudKit observation schema. The file contains page URLs and judgments, not the API key. The native app does not read the Bun collector database or run a digest. Model quality and a live provider response have not yet been verified for this build.

## Personal evaluation (0.3.0 development build)

Folder import includes Markdown notes and structured files named for bookmarks or YouTube watch history. Other export files, including direct messages, are skipped. Selecting one file explicitly accepts any listed format.

Choose **Filter notes with Base…** to select a notes folder and then an optional `.base` filter (use **Choose source…** for an unfiltered source). The chosen folder defines the collection; the Base may be anywhere, and moving it does not change the collection. Hidden files, packages and symbolic links are skipped. Zevra never infers a vault from the Base's parent directories. This source-first picker is a provisional UX to try with real data.

Base import reads the global filters and the single view named `All`. Both must match. The supported subset is `categories.contains(link("Name"))`, either as a filter string or in nonempty, nested `and` groups. Multiple required categories are supported. Other expressions (including status, `or`, negation, formulas and `this`), duplicate All views, duplicate filter keys, row limits, grouping and unknown selection properties stop the entire import with an explanation. Filters in other named views do not apply to All. Presentation fields such as column order, sort and summaries do not affect membership; import order is file path order.

The initial subset accepts YAML frontmatter whose `categories` is a list of simple, exact `[[Name]]` links. Path-qualified links, aliases and non-list categories are rejected rather than guessed. Missing categories do not match. Malformed or truncated properties stop the whole import; properties must close within the first 16 KiB. The Base is limited to 256 KiB, the collection to 5,000 Markdown files and the imported/profile candidates to 2,000. A Base import that exceeds a limit fails rather than returning partial results. Yams 6.2.2 parses YAML structurally. This is a limited importer, not the complete Obsidian expression or link-resolution engine. `Consumed` is never inferred to mean a positive rating.

#### Import decisions and practical trial (2026-09-24)

Accepted in the planning discussion: ask the user to point to a source; keep optional Base filtering independent of its location; apply every global/All selection condition or stop with a clear message. Unsupported forms can be added after testing concrete examples. Test the picker, compare the imported titles with the All view, move the Base and repeat, then add an unsupported condition and verify that the profile is unchanged. This practical trial with the user's data and a live TypeSafe response are still pending.

Verification of the local PR #3 correction: the pre-fix regression run failed for a Base at the source root (included a sibling collection), a deeply nested Base (missed selected notes), and three ignored/negated filter cases. After the correction, `sh macos/check.sh` passed Swift formatting, all 25 native tests (including parameterized cases), and the Apple Silicon Debug app build. The tests cover Base relocation/outside-source placement, symlink exclusions, combined global/view categories, malformed/unsupported filters and note properties, missing categories, and refusal to truncate a Base result. A scoped reuse/quality/efficiency review found no reuse change and led to keeping profile capacity handling in AppModel and avoiding a profile save when import adds nothing. A targeted manual diff review and `git diff --check` also passed. The picker interaction, import against the user's notes, live provider behavior and Intel execution have not been verified. These are local changes; no merge, release or app installation was performed.

### Reviewed source import and optional OpenAI analysis

The accepted flow is implemented locally: **Choose source… → review materials → optionally Analyze with OpenAI → review both result groups → Save approved results**. Folder and export selection, including a folder filtered by a Base, now opens an editable draft instead of saving immediately. Cancel discards it. The user can edit titles, links and topics and deselect materials. Supplied links are retained from Markdown frontmatter (`url`, `source`, `link`), JSON/JavaScript title records (`titleUrl`, `url`, `expanded_url`, `link`), HTML anchors and CSV URL/link columns. Unknown or unavailable links remain empty. Existing archive item IDs and ratings survive the optional URL/topic fields; approved edits update a matching item without clearing its rating.

OpenAI analysis is optional and explicit for each selected batch (up to 100 materials and 100 KB of input). The preview describes exactly what leaves the Mac: the selected titles, supplied links and source labels. Note bodies, local paths, the existing profile and provider keys are not part of model input. The user can still import locally without a key or network access. Analysis uses the Responses API with `gpt-4.1-mini`, a strict JSON schema and `store: false`, without tools, redirects or automatic retries. The user's OpenAI API key is kept in a separate, device-only Keychain entry; saving it does not call OpenAI. API billing and provider data handling still apply; `store: false` is not a claim of zero provider retention. Reference: [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs) and [model capabilities](https://developers.openai.com/api/docs/models/gpt-4.1-mini).

The model returns one material per source ID, with title and topic, plus suggested interests and intentions linked to source IDs. Zevra retains the supplied source and link rather than accepting invented ones from the model. It rejects missing/unknown/duplicate material identities, unsupported output shapes, excessive lengths, incomplete answers and refusals. Suggestions are hypotheses and start unchecked. Only explicitly selected interests are added; only explicitly selected intentions are appended to current goals. Existing goals and ratings are preserved, and the import does not enable Jev. Current link exclusions are checked again before sending and saving; accepted links use CapturePolicy normalization, including removal of fragments and tracking parameters. Edited invalid or blocked links must be corrected or their materials deselected. Nothing enters the persistent profile before approval; a failed save keeps the draft available.

The interface has a synthetic review demo, available through **Preview import review** in demo mode. A dedicated UI build can use `SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG SWIFT_PACKAGE ZEVRA_IMPORT_PREVIEW'` and `PRODUCT_BUNDLE_IDENTIFIER=com.jamatyka.Zevra.ImportPreview`; it uses only in-memory data and never reads or writes the installed profile or makes provider calls. The model protocol and transport tests use synthetic data and a URLSession protocol stub. Real OpenAI response quality, real-key Keychain interaction and real-source picker import remain unverified until the practical trial.

Verification — 2026-09-25: `sh macos/check.sh` passed formatting, 37 native tests and the Apple Silicon Debug build. Tests cover selected-only request fields, link sanitization, source identity validation, refusals/incomplete responses, HTTP failures, legacy profile decoding, edited/deselected results and preservation of ratings/goals. The review sheet was inspected in the isolated demo and its fields were edited. Saving exposed a SwiftUI `BindingOperations.ForceUnwrapping.get(base:)` crash during dismissal. The sheet now uses an explicit binding with a fallback value for dismissal and ignores writes after its draft is gone; the corrected build passes. The first replay was blocked by `cgWindowNotFound`; a subsequent live replay in the isolated post-fix demo passed both Save and Cancel. Saving one edited material and one edited intention changed the candidate count from 4 to 5, preserved the original goal and both existing interests, and retained 2 worthwhile / 2 not-worthwhile ratings. Cancelling another edited draft preserved that state. The sheet reopened successfully, and neither dismissal crashed. This verifies in-memory UI behavior, not disk persistence or live model analysis. No live provider request, merge, release or installed-app update was performed.

Practical acceptance before merge:

1. **Passed in the isolated demo (2026-09-25).** Open **Settings → Preview import review**, edit a title, deselect the other material and select one edited intention. Save must return to Settings without a crash, add one material and append the intention while preserving existing ratings, goals and unchecked interests.
2. **Passed in the isolated demo (2026-09-25).** Reopen the preview, edit a field and cancel. Profile counts, goals and ratings must stay unchanged; reopening the preview must work.
3. With a small user-selected source, verify that **Choose source…** only prepares a draft. Repeat with a Base outside the source and with an unsupported filter; the latter must fail without a partial import.
4. For the separate live OpenAI trial, review the selected titles/links first, then explicitly request analysis. Check both result groups, edit/deselect proposals and confirm that only approved changes survive reopening the app. An invalid key or cancelled analysis must leave the profile unchanged and allow retry.

A locally prepared `books-reading-list.json` can add Books titles as unrated candidates. Zevra does not access the Books library itself.

In **Settings → Personal evaluation**, choose a local folder or export to import candidate titles from Markdown, JSON, JavaScript, HTML or CSV. The app accepts Obsidian notes and locally supplied X/YouTube exports through the same picker. It reads only the chosen selection, keeps at most 2,000 titles, and does not copy note bodies into its profile. Imported titles indicate possible interest, not approval or reading completion. Review suggested topic words and add only interests that fit; selected interests can be removed or entered manually. Supply current goals separately and rate at least two worthwhile and two not-worthwhile examples. These ratings are the initial calibration; later visited pages can be rated from their row menu.

Personal evaluation is a separate opt-in after Jev is enabled. When it is on, the app pauses the earlier generic Jev suggestion path. For each eligible Arc page with at least ten cumulative active seconds and a public excerpt, it asks Jev for separate 0–4 scores for worth now, topical interest fit and current-goal fit. The row shows these estimates and flags low model confidence. A choice answer identifies whether the score was compared mainly with goals, rated examples, both or neither; this is not a free-form model explanation. No score means no judgment when the page or profile lacks enough evidence.

The profile and results are stored locally as `personal-profile.json` and `personal-evaluations.json` with owner-only file permissions. When the separate personal switch is on, a request to TypeSafe contains the public page title/domain/excerpt, current goals (up to 1,000 characters), up to 20 explicitly selected interests, and up to eight related positive and eight related negative example titles. Unrated archive titles stay local unless the user explicitly chooses OpenAI analysis in the import preview. Local title-word overlap selects the rated examples, so semantic synonyms may be missed. It does not send archive files, full notes, the full page URL or the full page body. Profile changes leave older scores visible with an **Older profile** label; a still-active or revisited page can be evaluated again. The feature has been tested with synthetic data and a local build, not a measured accuracy trial or a live TypeSafe request.

## Run locally

### 0.2.0 official release

The universal Release app passed the 11 native tests, Swift formatting and a Debug build. The repository check also passed 44 Bun tests, type checking, formatting, extension build and a synthetic demo. The Developer ID signature was verified, Apple accepted notarization submission `8b9a093e-9af9-4f4f-9672-f6190d9a3f5e`, its ticket was stapled, and Gatekeeper reported `accepted` / `Notarized Developer ID` after the final ZIP was extracted. The archive contains Apple Silicon and Intel binaries. The signed app was installed at `/Applications/Zevra.app` after backing up 0.1.1 in `macos/build/release-0.2.0/backups/`; application-support data and preferences were left in place. On this Mac the installed window opened, retained the existing launch-at-login setting, showed Jev off with no saved key, and reported that Accessibility access was needed, as the previous app did. A live Jev request, Intel execution, and first launch on another Mac were not tested.

### 0.2.0 development build verification

The 0.2.0 local build was compiled for Apple Silicon and Intel, signed with the same Developer ID team and bundle ID as the installed 0.1.1 app, and installed at `/Applications/Zevra.app`. The notarized 0.1.1 app was preserved in `macos/build/backups/Zevra-0.1.1-notarized.zip` (and an unpacked copy in that directory). The new local build has a valid Developer ID signature but no stapled notarization ticket; it is not a distributable release. The installed window displayed the existing four observations, retained Accessibility permission, and showed Jev off with no key. The full native check ran 11 tests and built the Debug app; the Release build and installed signature were also verified. A live Jev request and classification quality were not tested.

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

Capture requires an explicit per-installation opt-in, a URL permitted by the saved rules, Accessibility permission, an active Arc window, one unambiguous document in the accessibility tree, and recent input. URL rules run before the title is read or an observation is stored. Sensitive built-in domains, authentication-like routes and parameters, credentials, explicit ports, IP literals, and decoded `settings`, `login`, and `account` matches are rejected. This is a conservative subset of the original collector policy, not a complete detector of private pages or private browsing windows. Capture itself reads no page text, selected text, screenshots, or audio; optional Jev classification fetches public page text separately as described above.

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
