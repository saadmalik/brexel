# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`Brexel` is a macOS menu bar app (status item + popover, no Dock icon) that lists active Brex cards and copies card details on demand. Single-target Swift Package, macOS 13+, swift-tools-version 5.9. No test target exists.

## Common commands

```sh
swift run Brexel                     # run from source
swift build                          # debug build
swift build -c release               # release build (.build/release/Brexel)
Scripts/build-app.sh                 # bundle dist/Brexel.app + Info.plist + codesign
BREX_API_KEY='bxt_...' swift run Brexel      # seed Keychain at launch (only if Keychain is empty and token starts with bxt_)
```

`Scripts/build-app.sh` picks a code-signing identity in this order: `BREX_CODESIGN_IDENTITY` env var → `Brexel Local Signing` → `Developer ID Application:` → `Apple Development:` → ad-hoc. A stable identity is needed so macOS Keychain remembers `Always Allow` across rebuilds — don't switch identities casually.

## Architecture

Entry point is `AppDelegate.main()` (custom, not `@NSApplicationMain`), which sets `NSApplication.activationPolicy = .accessory` before `app.run()`. Combined with `LSUIElement=true` in the Info.plist (written by `build-app.sh`), this is what makes it a menu-bar-only app.

Layering:

- `StatusBarController` owns the `NSStatusItem` and an `NSPopover` whose content is a `NSHostingController` wrapping the SwiftUI `BrexelPopover` view. It also owns the single `BrexelModel`.
- `BrexelModel` (`@MainActor`, `ObservableObject`) is the only place UI state lives. It holds the cached token, the `[BrexCard]` list, per-user limit text, and the latest `AppMessage` for the toast/banner. Views read it via `@ObservedObject`.
- `BrexClient` is an `actor` wrapping `URLSession` against `https://api.brex.com`. All Brex calls go through its private generic `get` helper, which decodes errors into `BrexAPIError` (401/403 get user-friendly messages). `BrexCard`, `BrexClient`, and `BrexAPIError` reference the Brex API/company — they are *not* renamed when the app name changes.
- `KeychainStore` persists the token in the macOS Keychain under service `com.local.brexel`, account `brex-api-token`, with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Bundle id in the built `.app` is also `com.local.brexel` — keep these aligned or the Keychain item will be invisible to the bundled app.
- `LaunchAtLoginManager` wraps `SMAppService.mainApp`. `requiresApproval` is surfaced to the UI as a "approve in System Settings > Login Items" message — don't collapse it into a plain enabled/disabled boolean.

Brex API surface (all in `BrexClient`):

- `GET /v2/cards` — paginated via `next_cursor`, fetched eagerly on refresh. Filtered to `ACTIVE` + non-expired in `BrexCard.isActive` (don't move this filter into the API layer; the model relies on having the full list for limit lookups).
- `GET /v2/cards/{id}/pan` — fetched **on demand only**, when the user clicks a copy action for number/expiration/CVV/all-details. PAN/CVV are never persisted; they go straight to `NSPasteboard` via `Clipboard.copy`.
- `GET /v2/users/{id}/limit` — fetched only for cards whose `limit_type == USER`. A 403 short-circuits the loop (token likely lacks user read scope); other errors are silently skipped per-user.

Decoding notes:

- `CardListResponse` decodes items through `FailableDecodable<BrexCard>`, so a single malformed card in the list doesn't fail the whole page. Preserve this when adding fields.
- All Brex JSON uses snake_case; every model declares explicit `CodingKeys`. Date/expiration handling is custom (`CardExpiration` accepts both 4-digit and 2-digit years and computes `isExpired` against the local calendar).

Token bootstrapping (`BrexelModel.loadToken`): Keychain wins. Only if Keychain is empty *and* `BREX_API_KEY` is set *and* it starts with `bxt_` does the env var get written into the Keychain. After that the env var is ignored on subsequent launches.

## Conventions worth preserving

- `BrexelModel` is `@MainActor`; `BrexClient` is an `actor`. Don't call client methods from synchronous contexts — use `Task { await ... }` like `StatusBarController.init` does.
- User-visible errors flow through `AppMessage` (info/success/warning/error). Don't `print` or throw to the UI layer; map to a message instead.
- `BrexAPIError.errorDescription` is what the user sees — keep new error cases there, not in raw `String(describing:)`.
