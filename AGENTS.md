# Working on Attention Log

## Verification

- `bun run check`: formatting, TypeScript, tests, extension build, and demo. Runs each step in order, stops on failure, and uses a temporary ATTENTION_HOME.
- `bun test tests/<file>.test.ts`: verify a specific change.
- `bun run doctor --json`: read local configuration and check loopback health without calling an AI provider.
- `bun run format`: format code. Do not include formatting changes to unrelated files.
- After changing the extension, build it and reload it in the browser. A successful build alone does not verify visit capture.

## Code map

- `extension/tracker.ts`: active visit state, time accounting, and the queue.
- `extension/background.ts`: browser events and event delivery.
- `src/shared/policy.ts`: shared URL eligibility rules.
- `src/store.ts`: SQLite, deduplication, retention, and precedence of human decisions.
- `src/net.ts`, `src/enrich.ts`: public addresses, redirects, and content extraction.
- `src/jev.ts`: TypeSafe adapter; `src/digest.ts`: summary selection and storage.
- `src/cli.ts`, `src/mcp.ts`: user and agent interfaces.

Prefer the available code graph for symbol discovery. Use rg when the graph is unavailable or stale, or when searching text and configuration.

## Change boundaries

- Tests use temporary directories and synthetic data. Do not run tests against the user's private database.
- Do not print the collector token, provider keys, page excerpts, or browsing history in diagnostic logs.
- Do not send data to models during check, tests, or the demo. Testing a live provider is a separate step.
- Apply exclusions before storage and before sending data. Disabled mode and the absence of an explicit mode must retain safe defaults.
- Preserve event deduplication, exclusion of background time, and precedence of human corrections.
- Do not change scheduling, providers, or collection scope while cleaning up code. The user chose manual, local summaries.
- Do not change the original specification. Record decisions and test results in the project documentation.
- Describe evidence precisely: HTTP 200 from health does not verify visit delivery; a Jev key test does not verify recommendation quality.
