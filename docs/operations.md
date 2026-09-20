# Operations and live acceptance

Running `bun src/cli.ts serve` manually keeps the collector in the foreground; stop that instance with Ctrl+C. This Mac now uses the installed user LaunchAgent `~/Library/LaunchAgents/com.attention-log.collector.plist`, which starts at login and restarts the collector if it exits. Its label is `com.attention-log.collector`; logs are in `~/.local/share/attention-log/collector*.log`. Stop the installed service with `launchctl bootout gui/$(id -u)/com.attention-log.collector`; start it again with `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.attention-log.collector.plist`. Do not run a second foreground instance on the same port. The extension retains unsent events locally and retries once per minute; at 4,000 pending events it pauses capture and shows `!`. Restore connectivity, then save the extension settings to resume after the queue drains. This protects recorded evidence rather than silently dropping it.

Collection must pass both extension and collector policies. Saving in extension options automatically synchronizes the mode and site rules with the collector. The UI confirms when the collector has persisted and applied them; no restart is needed. If the collector is unavailable, the extension keeps the settings locally and retries at most once per minute until confirmed. Event delivery waits for confirmation, and newer saves supersede older acknowledgements. Capture enable/disable remains an extension setting; provider and summary settings are not changed. In `allow` mode, a missing allowed domain on either side means no stored page; `exclude` mode accepts other sites after applying exclusions. Other collector configuration is read at startup; manual edits to config.json still require a restart. Use extension options for site-rule changes. Use the extension's options page to inspect delivery errors. A healthy `/health` response does not prove the token or event delivery works.

## Manual summaries (current setup)

The user disabled automatic summaries on 2026-09-20. `com.attention-log.digest` is unloaded and its plist has no calendar, login, or keepalive trigger. The collector remains running with automatic Jev classification. No semantic summary agent is configured.

Generate today's local summary manually:

```sh
cd /Users/qb/Projects/jev-hister-keeper
bun --env-file=/Users/qb/.local/share/attention-log/typesafe.env src/cli.ts digest
```

Append `YYYY-MM-DD` to select another date. Output is in `~/.local/share/attention-log/digests/`. Each run processes new or changed page evidence and appends a section to the daily file. Unchanged inputs are skipped. A run processes at most 40 changed pages and reports any remaining backlog. The command performs enrichment/classification first, so enabled Jev may send eligible excerpts to TypeSafe; summary selection itself remains local.

The retained digest plist can be manually loaded and started, but has no automatic trigger. Running `scripts/configure-jev.py` preserves that absence of triggers.

## Live browser acceptance

Use a few non-sensitive allowed pages before collecting a full day. Inspect MCP results or the local SQLite database after each scenario.

1. Read a page for about 30 seconds, switch tabs, and confirm approximately 30 seconds of active time.
2. Leave another app focused; the browser tab must stop accumulating attention.
3. Switch among browser windows. Only the active tab of the focused window should count.
4. Navigate within the same tab. The old and new URL must have separate visits.
5. Stop/restart the extension service worker. Cumulative checkpoints must survive without doubling.
6. Restart the browser or sleep/wake the laptop. Downtime must not count. A checkpoint interval can be lost; long gaps deliberately undercount rather than manufacture attention.
7. Stop the collector, create activity, then restart it. Buffered UUIDs should replay once.
8. Select over forty characters, copy, scroll, and open a link in a background tab. Confirm each signal belongs to the source visit. Browser-created tabs whose destination is initially unavailable may not produce an opener signal.
9. Visit an excluded page and a URL with `?token=example`; neither should appear in extension pending data or SQLite.
10. Test Arc Spaces, Live Folders, link previews, and idle/lock separately. These browser/OS interactions are not established by the pure tracker tests.

Idle detection has a 60-second threshold. It is a behavioral approximation, not proof of reading. Background-tab scrolling never counts. Page bodies and selected strings are not sent by the extension.

## Two-week experiment

Start with five to ten public reading domains. Each morning record whether the list contained a page you actually revisited with `feedback <date> yes|no`. A missing evaluation is not a successful day. `stats` reports both evaluated and total digests for the most recent fourteen generated lists; it does not infer whether you closed tabs.

After fourteen days, compare useful lists with the source's target of at least half, and separately assess whether closing tabs feels easier. Inspect human corrections and heuristic/Jev disagreement in `verdict_history`. If the results are weak, revise scoring or abandon the idea before adding integrations.

## Recovery and limitations

- Failed extraction retries three times with increasing delays; it does not use your browser cookies or DOM. A failed page retains its title and heuristic evidence.
- Provider errors are recorded as a fallback reason, without logging private excerpts or credentials.
- Human decisions win until you change them explicitly; later machine scores can still update the shadow score.
- Re-running a saved digest preserves its contents. Human corrections affect later digests, not a historical snapshot.
- A changed policy stops future use but does not retract excerpts already sent or erase historical files.
- Do not run multiple collectors or nightly commands against the same runtime directory concurrently.
