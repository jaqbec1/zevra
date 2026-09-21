# Zevra

Zevra is a standalone Swift macOS app that records eligible Arc page URLs, titles, and estimated active time. No browser extension or local server is needed for the native app.

## Download the macOS preview

[Download Zevra 0.1.1 for macOS](https://github.com/jaqbec1/zevra/releases/download/v0.1.1/Zevra-macOS-universal.zip) · [Release notes and checksums](https://github.com/jaqbec1/zevra/releases/tag/v0.1.1)

Requires macOS 14 or later; supports Apple Silicon and Intel. Unzip and move `Zevra.app` to Applications, open it, grant Accessibility access, and enable capture. Allowed domains are optional. **Active time** is recorded foreground time; **Last seen** is the fixed date of the last observation.

This download is a **Developer ID–signed, Apple-notarized, local-only preview**. The notarization ticket is attached to the app. iCloud sync is not included in the download: the current iCloud build requires personal development provisioning. Separately provisioned development builds retain iCloud support. A notarized iCloud distribution build is not yet available.

Native setup and verification: [macOS documentation](docs/macos-prototype.md). To build a local preview, run `sh macos/check.sh` and `sh macos/package-preview.sh` with Xcode installed. Artifacts are written to `macos/build/artifacts/`. That script produces an ad-hoc-signed build; the public download additionally goes through Developer ID signing, Apple notarization, and ticket stapling before packaging.

## Original extension and collector

Attention Log records how much attention you give to web pages and creates a short list of material to read or keep. The extension runs in Arc and Chrome. Data goes into a local SQLite database; summaries are written as Markdown files.

This is a working experiment. Visit capture has been verified in Arc. Recommendation quality still needs evaluation during everyday use.

## What it adds to Hister

[Hister](https://github.com/asciimoo/hister) indexes the contents of pages and files so you can find them again. Its extension sends page content to the server. Attention Log measures active time, scrolling, selection, copying, and opening links. The service combines these signals with return visits and the categories `czytaj` (read), `utrwal` (keep), and `zapomnij` (forget).

Our extension sends no page text or selected text. It sends the URL, title, time, and gesture counts. The local service fetches content separately over HTTP, without browser cookies. As a result, it may not be able to read pages that require login, single-page applications, or paywalled articles.

This version runs independently of Hister. Its database, content fetching, and MCP interface partly duplicate Hister's features. Integration with Hister has not been built yet.

## Verify the project

Requires Bun 1.3.14 or later. Jev setup on macOS also uses Python 3.

```sh
bun install --frozen-lockfile
bun run check
```

`check` runs formatting checks, type checking, tests, the extension build, and the demo. It stops at the first failure. It uses a temporary `ATTENTION_HOME`; tests and the demo do not read browsing history or call a model. The build output goes to `dist/extension`.

```sh
bun run doctor
bun run doctor --json
```

`doctor` checks configuration, file permissions, and the local service's response. It does not print tokens, page content, or visited URLs. It does not test the Jev key with the provider. A service response does not prove that the extension is delivering visits.

## First run

```sh
bun run init
bun run build
```

Configuration is created at `~/.local/share/attention-log/config.json`. Set `ATTENTION_HOME` to use another directory. Keep data and keys outside the repository and synced directories.

1. In `config.json`, set `policy.mode`: `exclude` permits sites except those excluded; `allow` requires entries in `allowedDomains`.
2. Start the service with `bun start`. It listens on `127.0.0.1:3030`. Restart it after configuration changes.
3. In Arc or Chrome, open `chrome://extensions`, enable Developer mode, and load the `dist/extension` directory.
4. In the extension options, enter the token from the configuration and the same site policy. Enable capture.
5. Read an eligible page for at least a dozen seconds, switch tabs, and wait for delivery. The extension sends events every minute; the service fetches and classifies content every five minutes.

A new installation has capture and Jev disabled. An empty allowed-domain list blocks collection until you configure the policy.

## Saved pages

Click the Attention Log extension icon, or choose **View saved pages** in its options. The view lists saved pages with active time, scroll depth, return visits and classification. Switch between the default table and cards; your choice is saved locally. Lucide icons identify attention metrics, and classification details expand on demand. Search by title or URL; results are paginated, 50 per page. Choose **Refresh** to reload. The view requires the configured collector token and applies the current collector exclusions.

## Manual summaries

Without a date, the command selects today. Run it whenever you want to process new evidence:

```sh
bun run digest "$(date +%F)"
```

If Jev is enabled and the key was saved with the local setup script:

```sh
bun --env-file="$HOME/.local/share/attention-log/typesafe.env" src/cli.ts digest "$(date +%F)"
```

The file is written to `~/.local/share/attention-log/digests/YYYY-MM-DD.md`. Each run appends at most six items selected from new or changed pages within the preceding seven days. An empty list is a valid result.

Each run compares page evidence with the last processed version. New visits, additional attention and changed decisions can produce a new section in the daily file. Unchanged inputs are skipped. Up to 40 changed pages are processed per run; the command reports how many remain. Existing sections are retained. The first run after upgrading may reconsider older pages because previous versions did not record consumed inputs. The command first fetches content and runs classification: when enabled, Jev may send excerpts to TypeSafe at this stage. Summary selection remains local unless you configure `agentCommand`.

## Jev and data flow

Jev is optional. It receives the title, domain, an excerpt of up to 2,000 characters, word count, and attention metrics. It does not receive the full URL or the entire page. It returns a category and confidence; confidence below 0.6 requires review. A failed request falls back to local rules.

Classification is not personalized yet. Jev does not receive your goals, interests, projects, or previous corrections. Human corrections override machine decisions for that page, but are not used as examples for future classifications. The displayed Jev reason is a template containing its category and confidence, not an explanation of relevance to you.

For an existing installation with LaunchAgents:

```sh
python3 scripts/configure-jev.py
```

The script asks for the key without echoing characters. It saves the key to `~/.local/share/attention-log/typesafe.env` with permissions `600`, enables Jev, and reloads the services. It requires both existing LaunchAgent files; it is not an installer for a new computer. It does not enable a summary agent or add a schedule.

## Exclusions and storage

Save site rules in the extension options. They are applied to the running collector and persisted automatically, without restarting it. The status confirms application or shows a pending sync with automatic retries while the collector is offline.

Domain rules include subdomains. `excludedKeywords` matches substrings of the decoded URL without regard to case. The word `account` also excludes a public article if it appears in its URL.

Built-in rules block Gmail, ING, Cloudflare dashboards, local addresses, and URLs with authentication parameters, among others. They do not identify every private or authenticated page. See the [technical reference](docs/reference.md) for detailed rules and limitations.

Disabling capture removes pending events from the extension. A new exclusion blocks further processing of matching pages but does not remove old records or summaries. Visits, gestures, and event receipts expire after 90 days. Pages, decisions, and summaries remain. The application does not encrypt its files.

## Development

- [AGENTS.md](AGENTS.md): commands, data boundaries, and rules for changes.
- [Technical reference](docs/reference.md): MCP, the agent contract, scoring, and manual corrections.
- [Operations](docs/operations.md): services, logs, and browser checks.
- [Verification](docs/verification.md): completed checks and limits of the evidence.
- [Implementation plan](docs/plans/2026-09-19-0213-feat-attention-log-v0-plan.md) and [original specification](docs/specs/attention-log-v0.md).

In the current Arc installation, capture and Jev are enabled. Summaries are local and generated manually; scheduling remains disabled. This is not the default configuration for a new installation.
