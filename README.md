# Limitbar

A native SwiftUI menu bar app for connected Claude and Codex subscriptions. Written from scratch, with no third-party package dependencies and no code downloaded from another usage tracker.

**This is an initial implementation, not a verified macOS release.** The app bundle builds and passes local signature verification on a Mac. Core tests run with full Xcode selected. Live provider connections, including the experimental website reader, still need account testing.

## What works in this version

- A compact menu bar dropdown with a section for each connected subscription.
- Editable plan names and connection sources, with provider-reported usage windows and reset times.
- Automatic tracking only; unknown readings remain unavailable.
- Optional automatic Claude subscription readings via Claude Code's documented status line data.
- Optional automatic **Codex** allowance readings via the installed Codex CLI. This is not a universal counter for regular ChatGPT chats.
- Experimental Claude and Codex website readers with local sign-in windows; no CLI installation required. Codex has been exercised with a user account; the new Claude reader still needs live-account validation.
- A check of connected sources every 60 seconds, with explicit connection errors and stale readings after 15 minutes.
- Local JSON storage. A damaged configuration is left untouched and editing is disabled until it can be loaded again.

**Google AI web usage and regular ChatGPT web chat usage are not supported yet.** Manual entry is no longer available. This app does not assume that API billing data represents subscription usage, estimate plan percentages from token counts, or claim that unknown usage is zero.

## Build on your Mac

Requires macOS 14 or later and Xcode 15 or later (Swift 5.9+). Copy this project folder to your Mac, then run these commands from its directory:

```sh
swift test
bash Scripts/build-app.sh
open dist/Limitbar.app
```

Install full Xcode, open it once to finish setup, and select it under **Xcode → Settings → Locations → Command Line Tools**. Standalone Command Line Tools may lack XCTest or required SwiftUI compiler plugins. The build script automatically uses `/Applications/Xcode.app` when the standalone tools remain selected and `DEVELOPER_DIR` is unset. You can also open `Package.swift` in Xcode and choose the **Limitbar** executable scheme. Use the build script for the complete `.app` bundle, which includes the Claude bridge.

The build script creates an app bundle and signs it locally with an ad hoc signature. It does not download dependencies, install another tracker, or publish anything. Distribution to other people would require a separate signing and notarization setup.

For permanent use, move `dist/Limitbar.app` into Applications using Finder, then launch that copy. The gauge icon appears in the menu bar; the app has no Dock icon. Click **Manage plans → Connections** to connect Claude or Codex. New installations start with no placeholder subscriptions; a website plan is added after a successful connection.

## Existing manual subscriptions

Manual entry has been removed. On upgrade, existing manual plans and their snapshots are retained in the `archivedManualPlans` field of the local `plans.json` for recovery, and are removed from the active subscription list. Connected website and CLI plans are preserved. Gemini and other unsupported providers cannot be added until an automatic connection is available.

## Connect Claude website (prototype)

1. Open **Manage plans → Connections → Connect Claude website…**.
2. Sign in inside Limitbar. The **Usage page** button opens `https://claude.ai/new#settings/usage`.
3. Once **Your usage** shows **Current session** and **This week**, click **Read usage & connect**.
4. A successful read adds **Claude · Website**. Existing connected plans stay as they are.

The reader checks the page every minute while the app runs, including when its browser window is closed. The local website session persists across app launches, independently of Codex's session. Sign in again if Claude expires the session. **Disconnect and clear Claude website session** clears only the Claude session and removes its website plan from the active list.

Only explicitly labeled quota percentages are imported. Reset clocks such as **Resets at 6:30 PM** and **Resets Tuesday 11:00 PM** are interpreted in the Mac's local time zone and marked approximate because their dates are inferred. Unrecognized reset formats remain unknown. Embedded sign-in or changes to the page layout can prevent connection. The parser and browser extraction are tested against representative HTML based on the supplied screenshot; live Claude sign-in still needs testing.

## Connect Claude Code (optional)

This needs a Claude Code version that provides `rate_limits` in its status line JSON, signed into your Claude subscription. The bridge only receives new values while Claude Code is active; changes from another device are not continuously polled.

1. Move the bundled app to its permanent location and launch it.
2. In **Manage plans → Connections**, copy the Claude configuration snippet.
3. Merge its `statusLine` entry into `~/.claude/settings.json` yourself, preserving other settings. If you already have a status line, this replaces it; the app does not edit that file for you.
4. Edit the Claude plan and choose **Claude Code status line** as its source.
5. Start a new Claude Code session and use it. Subscription limits appear when Claude Code provides them after a response.

The snippet points at `Limitbar.app/Contents/MacOS/LimitbarBridge`. Moving the app later requires updating that path. The bridge consumes stdin, extracts only quota fields, and atomically writes `claude-usage.json`. It does not store the original payload, transcript paths, or prompts. Absent windows remain unavailable. Unsupported plans or older CLI versions may not report limits.

See Anthropic's [status line documentation](https://code.claude.com/docs/en/statusline) and [usage limit explanation](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work).

## Connect Codex website (prototype)

1. Open **Manage plans → Connections → Connect Codex website…**.
2. Sign in on the website inside Limitbar. This is a separate WebKit session from Safari or Chrome.
3. Open the English Codex usage page, then click **Read usage & connect**.
4. A successful read adds a separate **Codex · Website** plan. Existing plans are preserved. The page reloads every minute while the app runs, including when the connection window is closed.

This prototype reads only recognized, visible quota cards with explicitly labeled used/remaining percentages. It does not use an official website-usage API, scrape conversations, import another browser's cookies, or extract authentication tokens. It supports five-hour, weekly, and code review cards when recognizable. Reset dates use an exact timestamp when the page exposes one. Explicit countdowns such as “Resets in 3h 29m” produce an approximate reset time, labeled “Resets in about” in the dashboard; clock text without a date/time zone remains unavailable. The reader supports both the older Codex routes and the unified `/settings/usage` page. Unsupported layouts, other languages, expired sessions, and sign-in providers that block embedded browsers can prevent readings. Failed refreshes preserve the last reading and mark it unavailable/stale rather than inventing new usage.

The website session persists in WebKit's local storage for Limitbar. **Disconnect and clear website session** removes that session and its website plan from the active list. Tests use synthetic quota cards and HTML; they do not establish compatibility with a live account. This connection describes the account currently signed into the embedded website.

## Connect Codex CLI (optional)

Install the official Codex CLI yourself and sign in with `codex login` using your ChatGPT subscription. In the ChatGPT plan editor choose **Codex CLI**. Standard Homebrew and local install locations are detected; for other locations, set the absolute path reported by `which codex` in **Connections**.

The app runs `codex app-server` over a local pipe, initializes the connection, reads the account, and requests `account/rateLimits/read`. It does not create a model thread or turn. The CLI owns authentication and may refresh its credentials. The integration rejects API-key-only logins, displays all returned quota buckets, and bounds each refresh to 20 seconds. Readings describe the **active CLI account**. Each connection source tracks one active account.

See OpenAI's [app-server documentation](https://developers.openai.com/codex/app-server) and [Codex plan usage guidance](https://developers.openai.com/codex/pricing). Google documents its usage display in [Gemini Apps limits](https://support.google.com/gemini/answer/16275805?hl=en); no automated Google web integration is included here.

## Data and source layout

The app writes `plans.json` and optional `claude-usage.json` under `~/Library/Application Support/Limitbar/`, with owner-only file permissions. The website reader uses a persistent local WebKit session; it does not access Safari/Chrome cookie stores or save raw website contents. There is no telemetry, cloud sync, app-managed password storage, or automatic login item. The website and connected CLIs contact their providers.

```text
Sources/Limitbar/         SwiftUI menu panel, settings, and plan editor
Sources/LimitbarCore/     Quota models, decoders, Codex RPC client, persistence
Sources/LimitbarBridge/   Small Claude Code status line executable
Tests/LimitbarCoreTests/  Decoder, stale/reset, persistence, and fake-CLI tests
Scripts/build-app.sh     Builds and locally signs the app bundle
```

`swift test` includes tests for unknown usage, multiple quota buckets, invalid data, timestamp handling, stale readings, configuration preservation, RPC initialization, timeout behavior, and API-key login rejection. Fake CLI tests do not contact providers. The macOS GitHub Actions workflow runs tests and builds the bundle if you choose to push this project to GitHub; it has not been run as part of the Windows development session.
