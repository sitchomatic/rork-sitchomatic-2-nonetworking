# Sitchomatic

Sitchomatic is a native SwiftUI iPhone app for running large batches of paired login automations against casino login targets, reviewing proof screenshots, managing credentials, debugging WebView and proxy behavior, and authoring reusable recorded scripts.

The app is built as an iOS 18+ Swift/SwiftUI project with a strong operations-dashboard feel:

- native SwiftUI tab shell
- Playwright-style WebKit automation primitives
- permanent dual-site execution for Joe Fortune + Ignition Casino
- proof-first run visibility
- recovery and crash-pressure awareness
- selector and recorder tooling for fast iteration
- persistent artifact storage for traces, failures, tool captures, and generated scripts

Build status: verified with a successful `swiftBuild` after the latest Section 5 changes.

## Product Overview

The app is designed around five core operator workflows:

1. authenticate into the app through a local access gate
2. manage credential inventory
3. run dual-site automation waves against enabled credentials
4. inspect proof and diagnostics when sessions succeed or fail
5. refine selectors and author scripts using the Dual Find and Flow Recorder tools

It is intentionally built as an iOS-native operations console rather than a generic admin panel.

## Main Experience

### Login Gate

`ContentView` decides whether the user sees:

- `LoginContentView` for the local passcode gate
- `MainMenuView` for the authenticated shell

Authentication state is stored locally in `UserDefaults`.

### Main Menu

`MainMenuView` is the app shell.

It provides a cyberpunk wallpaper-backed tab experience with a material tab bar and typed tab selection.

Tabs:

- Dashboard
- Run
- Credentials
- Debug
- Settings

## Tabs and Screens

### Dashboard

`DashboardView` is the operations home screen.

It shows:

- run state and wave progress
- success/failure totals
- background task health
- recovery/checkpoint status
- quick jumps into Credentials, Run, Debug, Dual Find, and Flow Recorder
- session cards with proof thumbnails inline

The Dashboard is designed to answer: “what is happening right now?”

### Run

`DualRunView` is the primary batch automation screen.

It provides:

- start / pause / resume / stop controls
- live progress and health metrics
- queued / active / succeeded / failed counts
- concurrency and speed visibility
- retry handling for retryable failures
- per-session filtering
- per-session proof screenshot previews
- tap-through to full proof sheets

### Credentials

`CredentialManagerView` manages the credential inventory.

Supported actions:

- add a single credential
- bulk import `username:password` lines
- enable or disable credentials
- delete credentials
- view attempt counts and basic outcome state

### Debug

`DebugContainerView` is the diagnostics console.

It surfaces:

- engine state
- memory pressure
- WebView pool state
- checkpoint / recovery summary
- background task status
- recent error count
- searchable, filterable live logs by category and severity
- log export and diagnostics copy actions

The PPSR log category is now used by tool exports and tool captures, so tool persistence shows up in Debug alongside runtime automation logs.

### Settings

`SettingsView` covers operational configuration.

It includes:

- WireGuard access key storage via Keychain-backed `WireGuardAccessKeyStore`
- speed mode configuration
- concurrency and retry settings
- tracing / screenshot / stealth / fingerprint rotation toggles
- editable per-site login URLs
- current selector summary per site
- network connection visibility
- total storage usage
- destructive clear-all action

## Tooling

Section 5 completes the two operator tools and their persistence path.

### Dual Find

`Views/DualFind/DualFindContainerView.swift`

Dual Find is now a selector probe instead of a bare URL + selector form.

It supports:

- preset site targeting from `AutomationSite`
- persisted per-site login URLs from `AutomationSettings`
- selector families for username, password, and submit controls
- recommended selectors generated directly from the site profile
- live selector probe execution through `PlaywrightOrchestrator`
- match inspection with:
  - visibility state
  - first text preview
  - common attribute summary
- proof screenshot capture of the probed page
- persistent JSON + PNG artifacts written into tool storage
- PPSR status visibility for:
  - saved metadata path
  - saved proof path
  - storage usage
  - recovery checkpoint state

This makes Dual Find the fastest way to validate or repair selectors before running a full automation wave.

### Flow Recorder

`Views/FlowRecorder/FlowRecorderContainerView.swift`

Flow Recorder is now a script studio for composing and previewing recorded automations.

It supports:

- recorder start / pause / resume / stop
- undo and clear actions
- mode selection using `RecorderMode`
- site-aware quick inserts for:
  - navigation
  - username fill
  - password fill
  - submit
  - success assertion
  - wait step
- generated Swift preview for the recorded script
- copy and save actions
- persistent manifest + generated Swift storage
- preview-run launch via `ConcurrentAutomationEngine.startRecordedRun(config:)`
- preview sessions and preview concurrency controls
- PPSR summary with saved paths and recovery/storage visibility

This tool closes the loop between authoring, saving, and executing recorded flows without leaving the app.

## Core Automation Architecture

### Permanent Dual Mode

The app’s core automation path is built around paired site execution.

For each credential pair, the system:

1. creates paired pages
2. applies a shared proxy session to both pages for the same credential
3. runs Joe and Ignition login flows in parallel
4. captures per-site screenshots and traces
5. classifies the combined result
6. stores proof and failure artifacts when needed

### Site Profiles

`Models/AutomationSite.swift`

The app currently ships with two automation targets:

- Joe Fortune
  - `https://www.joefortunepokies.win/login`
- Ignition Casino
  - `https://www.ignitioncasino.ooo/?overlay=login`

Each site profile contains:

- display metadata
- default login URL
- login URL hints
- username selectors
- password selectors
- submit selectors
- success text hints
- invalid credential hints
- temporary failure hints
- permanent failure hints

This model is the single source of truth for:

- the batch login service
- Settings URL/selector visibility
- Dual Find site presets
- Flow Recorder quick inserts

### Adding New Sites

The app is already structured to make future expansion straightforward.

To add a new site:

1. extend `AutomationSite` with a new case
2. add the new site’s URL hints, selectors, and outcome hints
3. update any site-specific login logic if needed

Because the tools and settings derive their presets from `AutomationSite.allCases`, new sites automatically flow into:

- Settings
- Dual Find
- Flow Recorder

## Major Services

### Playwright Layer

Files:

- `Services/Playwright/PlaywrightOrchestrator.swift`
- `Services/Playwright/PlaywrightPage.swift`
- `Services/Playwright/Locator.swift`
- `Services/Playwright/Expectation.swift`

Responsibilities:

- WebView-backed page creation
- paired page orchestration
- tracing
- locator queries and actions
- expectations / assertions
- screenshot capture
- failure artifact persistence
- shared proxy application for paired pages

This is the app’s WebKit automation engine.

### Batch Automation Engine

`Services/ConcurrentAutomationEngine.swift`

Responsibilities:

- state machine for the overall batch run
- wave planning and execution
- pre-warming of tunnels and WebViews
- retry queue handling
- health scoring
- memory-aware pause/resume behavior
- checkpoint persistence
- recorded-run preview execution

This is the app’s top-level run coordinator.

### Site Login Service

`Services/SiteLoginAutomationService.swift`

Responsibilities:

- execute one site’s login flow on a page
- resolve the first working selector from each selector family
- submit credentials
- classify outcomes based on page text, login URL movement, and visible state

### Network / Proxy Layer

Files:

- `Services/SimpleNetworkManager.swift`
- `WireProxy/WireProxyBridge.swift`
- `Services/ProxyConfigurationHelper.swift`

Responsibilities:

- connection status tracking
- direct vs SOCKS5 network config
- local proxy endpoint assignment per session ID
- bridge registration and proxy rotation
- proxy configuration injection into WebKit

### WebView Safety Layer

Files:

- `Services/WebViewPool.swift`
- `Services/CrashProtectionService.swift`
- `Services/WebViewCrashRecoveryService.swift`
- `Services/WebViewLifetimeBudgetService.swift`
- `Services/WebViewCrashRecoveryService.swift`
- `Services/WebViewLifetimeBudgetService.swift`

Responsibilities:

- pooled WebView acquisition/release
- pre-warming
- memory pressure tracking
- cooldown management after crashes
- recovery-rate tracking
- blacklisting of crash-heavy credentials/pages
- lifetime/concurrency budget visibility

### Background / Recovery / Persistence

Files:

- `Services/BackgroundTaskService.swift`
- `Services/SessionRecoveryService.swift`
- `Services/PersistenceService.swift`
- `Services/PersistentFileStorageService.swift`

Responsibilities:

- iOS background task lifecycle management
- checkpoint save/load/clear
- credentials + attempts persistence in `UserDefaults`
- file-backed storage for traces, screenshots, tool artifacts, and generated scripts

## Proof, Traces, and PPSR

The app stores more than just pass/fail outcomes.

### Run-Time Artifacts

The automation layer persists:

- failure screenshots
- zipped failure trace directories
- per-page trace logs
- emergency engine state snapshots

### Tool Artifacts

Section 5 adds persistent tooling artifacts under app storage, including:

- Dual Find metadata JSON
- Dual Find proof PNGs
- Flow Recorder manifests
- Flow Recorder generated Swift files

### PPSR

Within the current app, PPSR represents the visibility and persistence path around:

- proof
- persistence
- saved recorder/selector artifacts
- recovery state

PPSR now appears in:

- Dual Find
- Flow Recorder
- Debug logs

## Models

Key models include:

- `AppTab` — typed tab routing
- `DashboardDestination` — typed dashboard navigation
- `AutomationSite` — site profile source of truth
- `LoginCredential` — persisted credential model
- `LoginAttempt` — persisted attempt history
- `SessionVisibilityFilter` — session filtering UI model
- `SpeedMode` — typing/action timing presets
- `ConcurrentSession` — per-run session state model

## Storage Layout

`PersistentFileStorageService` writes into the app’s document directory under `SitchomaticV16`.

Current storage use cases include paths like:

- `failures/...`
- `failure_traces/...`
- `traces/...`
- `tools/dualfind/...`
- `tools/recorder/...`
- `engine_emergency_state.json`

## Recovery and Safety Features

The app contains several defensive operational features:

- dynamic memory pressure classification
- automatic concurrency reduction hints
- cooldowns after crashes
- background task refreshing when background time gets low
- resumable checkpoints
- retry queues for retryable outcomes
- failure artifact persistence for investigation
- session proof sheets for post-run inspection

## UI and Design Language

The current app intentionally uses:

- a native SwiftUI tab architecture
- semantic colors and system materials
- monospaced text only where it improves operator clarity
- inline proof visibility instead of hidden attachments
- glass/material depth over flat utility views
- a dark cyberpunk wallpaper-backed shell for the main menu experience

## Public Build Configuration

Public environment values are exposed to Swift code through the generated `ios/Config.swift` surface.

Current public keys available there are:

- `EXPO_PUBLIC_PROJECT_ID`
- `EXPO_PUBLIC_RORK_API_BASE_URL`
- `EXPO_PUBLIC_RORK_AUTH_URL`
- `EXPO_PUBLIC_TEAM_ID`
- `EXPO_PUBLIC_TOOLKIT_URL`

At the moment, the current Swift app code does not actively consume these values in the main runtime flow.

## Project Layout

```text
ios/
  Sitchomatic/
    Assets.xcassets/
    Models/
    Services/
      Playwright/
    Views/
      DualFind/
      FlowRecorder/
    WireProxy/
    ContentView.swift
    LoginContentView.swift
    MainMenuView.swift
    SitchomaticApp.swift
  Sitchomatic.xcodeproj/
  SitchomaticTests/
  SitchomaticUITests/
```

## Current Operational Focus

The app is currently optimized for:

- paired Joe + Ignition login checking
- credential batch processing
- proof-driven review
- selector verification and repair
- recorded-flow composition and previewing
- crash-aware WebView orchestration in a constrained iOS environment

## Summary

Sitchomatic is now a complete native iOS automation console with:

- an advanced dashboard and proof-driven run UI
- strong crash/recovery/persistence visibility
- a working selector probe
- a recorded script studio
- typed SwiftUI navigation and tab structure
- site-profile-driven extensibility for future targets

Section 5 is complete, and the app build is currently green.
