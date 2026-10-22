# Limitbar

A native SwiftUI menu bar app for your Claude, ChatGPT, and Google AI subscriptions. Written from scratch, with no third-party package dependencies and no code downloaded from another usage tracker.

**This is an initial implementation, not a verified macOS release.** Development took place on Windows without a Swift toolchain. The app, Swift tests, and provider connections still need to be built and exercised on a Mac.

## What works in this version

- A menu bar panel with a separate card for each subscription.
- Editable plan names, multiple usage windows, percentages used, and reset times.
- Manual tracking for all plans; unknown values remain unknown.
- Optional automatic Claude subscription readings via Claude Code's documented status line data.
- Optional automatic **Codex** allowance readings via the installed Codex CLI. This is not a universal counter for regular ChatGPT chats.
- A check of connected sources every 60 seconds, with explicit connection errors and stale readings after 15 minutes.
- Local JSON storage. A damaged configuration is left untouched and editing is disabled until it can be loaded again.

**Automatic tracking of Google AI web usage and regular ChatGPT web chat usage is not implemented.** These use manual entries. This app does not assume that API billing data represents subscription usage, estimate plan percentages from token counts, or claim that unknown usage is zero.

## Build on your Mac

Requires macOS 14 or later and Xcode 15 or later (Swift 5.9+). Copy this project folder to your Mac, then run these commands from its directory:

```sh
swift test
bash Scripts/build-app.sh
open dist/Limitbar.app
```

If developer tools are missing, install Xcode or run `xcode-select --install` first. You can also open `Package.swift` in Xcode and choose the **Limitbar** executable scheme. Use the build script for the complete `.app` bundle, which includes the Claude bridge.

The build script creates an app bundle and signs it locally with an ad hoc signature. It does not download dependencies, install another tracker, or publish anything. Distribution to other people would require a separate signing and notarization setup.

For permanent use, move `dist/Limitbar.app` into Applications using Finder, then launch that copy. The gauge icon appears in the menu bar; the app has no Dock icon. Click **Manage plans** to edit the three initial subscriptions. Their usage starts as unavailable until you enter readings or connect a supported source.

## Manual subscription tracking

1. Open **Manage plans**, then **Edit** on a subscription.
2. Set your actual plan name and leave **Usage source** on **Manual entry**.
3. Add a window for each limit the provider shows, such as session, weekly, or a model-specific allowance.
4. Enter the percentage **used**, with an optional reset date. If a provider shows remaining usage, subtract it from 100. Leave the percentage blank if it is unknown.

Refreshing does not modify manual entries. Once a reset time passes, the app labels that reading as awaiting an update; it never assumes a new zero-usage window. The individual card shows the source and age of each reading.

## Connect Claude Code (optional)

This needs a Claude Code version that provides `rate_limits` in its status line JSON, signed into your Claude subscription. The bridge only receives new values while Claude Code is active; changes from another device are not continuously polled.

1. Move the bundled app to its permanent location and launch it.
2. In **Manage plans → Connections**, copy the Claude configuration snippet.
3. Merge its `statusLine` entry into `~/.claude/settings.json` yourself, preserving other settings. If you already have a status line, this replaces it; the app does not edit that file for you.
4. Edit the Claude plan and choose **Claude Code status line** as its source.
5. Start a new Claude Code session and use it. Subscription limits appear when Claude Code provides them after a response.

The snippet points at `Limitbar.app/Contents/MacOS/LimitbarBridge`. Moving the app later requires updating that path. The bridge consumes stdin, extracts only quota fields, and atomically writes `claude-usage.json`. It does not store the original payload, transcript paths, or prompts. Absent windows remain unavailable. Unsupported plans or older CLI versions may not report limits.

See Anthropic's [status line documentation](https://code.claude.com/docs/en/statusline) and [usage limit explanation](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work).

## Connect Codex (optional)

Install the official Codex CLI yourself and sign in with `codex login` using your ChatGPT subscription. In the ChatGPT plan editor choose **Codex CLI**. Standard Homebrew and local install locations are detected; for other locations, set the absolute path reported by `which codex` in **Connections**.

The app runs `codex app-server` over a local pipe, initializes the connection, reads the account, and requests `account/rateLimits/read`. It does not create a model thread or turn. The CLI owns authentication and may refresh its credentials. The integration rejects API-key-only logins, displays all returned quota buckets, and bounds each refresh to 20 seconds. Readings describe the **active CLI account**. There is one automatic connection per service; additional accounts can be tracked manually.

See OpenAI's [app-server documentation](https://developers.openai.com/codex/app-server) and [Codex plan usage guidance](https://developers.openai.com/codex/pricing). Google documents its usage display in [Gemini Apps limits](https://support.google.com/gemini/answer/16275805?hl=en); no automated Google web integration is included here.

## Data and source layout

The app writes `plans.json` and optional `claude-usage.json` under `~/Library/Application Support/Limitbar/`, with owner-only file permissions. There is no telemetry, cloud sync, password storage, browser-cookie access, or automatic login item. Connected CLIs can make requests to their own providers.

```text
Sources/Limitbar/         SwiftUI menu panel, settings, and plan editor
Sources/LimitbarCore/     Quota models, decoders, Codex RPC client, persistence
Sources/LimitbarBridge/   Small Claude Code status line executable
Tests/LimitbarCoreTests/  Decoder, stale/reset, persistence, and fake-CLI tests
Scripts/build-app.sh     Builds and locally signs the app bundle
```

`swift test` includes tests for unknown usage, multiple quota buckets, invalid data, timestamp handling, stale readings, configuration preservation, RPC initialization, timeout behavior, and API-key login rejection. Fake CLI tests do not contact providers. The macOS GitHub Actions workflow runs tests and builds the bundle if you choose to push this project to GitHub; it has not been run as part of the Windows development session.
