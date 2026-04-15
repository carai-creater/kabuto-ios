# kabuto-ios

Native iOS (SwiftUI) client for [kabuto](https://github.com/carai-creater/kabuto) — the Japanese AI-agent marketplace.

This project mirrors the feature set of the existing Next.js web app without changing its behavior or domain model. The existing Next.js backend is the source of truth; this app talks to it via a new `/api/v1/*` REST layer (to be added in kabuto).

## Status — Phase 1 (foundation)

- [x] Xcode project (filesystem-synchronized groups)
- [x] SwiftUI `@main` + root `TabView`
- [x] `AppEnvironment` DI container
- [x] `AppConfig` loading from Info.plist (injected via xcconfig — no hardcoded secrets)
- [x] `APIClient` skeleton (URLSession, bearer-token provider hook)
- [x] `AuthService` skeleton + `SessionStore` (Keychain-backed)
- [x] Feature placeholders for Home / Marketplace / Wallet / Profile
- [x] Unit test target with `AppConfig` tests
- [ ] Supabase Swift SDK wiring — Phase 2
- [ ] Real endpoints / chat streaming / StoreKit — Phase 3+

## Requirements

- macOS with Xcode 16 or newer (developed on Xcode 26.3)
- iOS 17.0 deployment target
- iPhone only (iPad support is a later phase)

> **Note on building from the command line:** this machine currently does not
> have the iOS platform bundle installed (only the simulator SDK). To run
> `xcodebuild` you need to install the iOS platform in
> `Xcode → Settings → Components`. For syntax/type checking without the full
> platform install, see `make typecheck` below.

## Setup

1. **Clone**
   ```sh
   git clone <this-repo> kabuto-ios && cd kabuto-ios
   ```

2. **Create your local secrets file** — `Config/Secrets.xcconfig` is gitignored.
   ```sh
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   ```
   Then edit `Config/Secrets.xcconfig` and fill in:
   - `KABUTO_API_BASE_URL` — URL of the kabuto Next.js backend (e.g. `https://kabuto.example.com`). In URLs the `//` must be escaped as `/$()/` because xcconfig treats `//` as a comment.
   - `KABUTO_SUPABASE_URL` — your Supabase project URL
   - `KABUTO_SUPABASE_ANON_KEY` — Supabase publishable/anon key

3. **Open the project** in Xcode
   ```sh
   open KabutoiOS.xcodeproj
   ```
   Select the `KabutoiOS` scheme and an iOS 17+ simulator, then Build & Run (⌘R).

## Project layout

```
kabuto-ios/
├── Config/
│   ├── Debug.xcconfig            # Debug build settings + Info.plist injection
│   ├── Release.xcconfig
│   ├── Secrets.example.xcconfig  # Template — copy to Secrets.xcconfig
│   └── Secrets.xcconfig          # gitignored
├── KabutoiOS/
│   ├── App/
│   │   ├── KabutoApp.swift       # @main entry point
│   │   ├── AppEnvironment.swift  # DI container (@Observable)
│   │   └── RootView.swift        # Root TabView
│   ├── Core/
│   │   ├── Config/AppConfig.swift
│   │   ├── Networking/           # APIClient, APIEndpoint, APIError
│   │   ├── Auth/                 # AuthService, SessionStore, KeychainStorage
│   │   └── Logging/Log.swift     # OSLog categories
│   ├── Features/                 # feature-first: Home, Marketplace, Wallet, Profile
│   └── Resources/
│       └── Assets.xcassets/      # AppIcon, AccentColor
├── KabutoiOSTests/               # Unit tests
└── KabutoiOS.xcodeproj/
    ├── project.pbxproj           # uses PBXFileSystemSynchronizedRootGroup
    │                             # (Xcode 16+): sources auto-discovered from
    │                             # the KabutoiOS/ folder — no per-file entries
    └── xcshareddata/xcschemes/KabutoiOS.xcscheme
```

### Architecture

- **feature-first + MVVM.** Each feature folder owns its Views and (later) its ViewModels and Services.
- **Swift Concurrency.** All async work uses `async`/`await` and actor isolation. `@MainActor` on UI-facing types.
- **Observation framework.** `@Observable` for state types, `Environment(...)` for dependency injection through the view tree.
- **Config injection.** xcconfig → Info.plist → `AppConfig.loadFromBundle()`. No hardcoded URLs, keys, or flags anywhere in source.
- **Networking.** `APIClient` actor. `APIEndpoint<Response>` phantom-typed. Endpoint catalogs live in each feature folder.
- **Auth.** Supabase session envelope stored in Keychain via `SessionStore` + `KeychainStorage`. Phase 2 wires `supabase-swift` as the driver; the `AuthService` contract stays stable.
- **Error handling.** `APIError` for network, `AuthError` for auth, `KeychainError` for storage — each with human-readable descriptions for logging.

## Security posture

- **No secrets in source code.** Keys and endpoints come from `Config/Secrets.xcconfig` (gitignored).
- **Keychain-only session storage.** No `UserDefaults`, no plist, no filesystem. `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- **Bearer tokens only in `Authorization` headers.** Never in URLs or query strings.
- **Financial actions routed via StoreKit** (planned Phase 5). Stripe web checkout is deliberately NOT used on iOS.

## Backend contract (to be added to kabuto)

Phase 1 establishes the client shape. The kabuto repo needs a matching `/api/v1/*` layer, which is the work of Phase 2+ on the server side. Planned endpoints:

| Feature | Endpoint | Notes |
|---|---|---|
| Auth | handled by Supabase Swift SDK | no custom endpoint |
| Me / profile | `GET /api/v1/me` | returns User + Profile + Wallet balance |
| Marketplace list | `GET /api/v1/agents` | query: `q`, `tag`, `sort` |
| Agent detail | `GET /api/v1/agents/:slug` | includes reviews, starters |
| Chat stream | `POST /api/v1/chat` (SSE) | same contract as current `/api/chat` |
| Wallet history | `GET /api/v1/wallet/history` | paginated transactions |
| StoreKit grant | `POST /api/v1/wallet/iap/grant` | server-side receipt validation → wallet credit |
| Reviews | `POST /api/v1/agents/:slug/reviews` | |
| Favorites | `POST / DELETE /api/v1/agents/:slug/favorite` | |
| MCP | `GET / POST / DELETE /api/v1/mcp/connections` | |
| Agent CRUD | `GET/POST/PATCH/DELETE /api/v1/creator/agents` | |

Existing Server Actions in kabuto stay — the new API layer is a thin adapter so the iOS client can reach the same business logic.

## Verification without a full iOS platform install

On machines that only have the simulator SDK (no device platform), use:

```sh
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
find KabutoiOS -name "*.swift" -print0 \
  | xargs -0 swiftc -typecheck -target arm64-apple-ios17.0-simulator -sdk "$SDK"
```

For a full build & run:
```sh
xcodebuild -project KabutoiOS.xcodeproj \
           -scheme KabutoiOS \
           -configuration Debug \
           -destination 'platform=iOS Simulator,name=iPhone 15' \
           build
```

## Roadmap

| Phase | Scope |
|---|---|
| 1 | **(this)** Foundation: project, DI, config, API client, auth skeleton |
| 2 | Supabase Swift SDK wiring, Login/Signup screens, session persistence |
| 3 | Marketplace + agent detail + reviews (read side) |
| 4 | Chat streaming (SSE client), model picker, conversation starters |
| 5 | Wallet + StoreKit in-app purchase, transaction history |
| 6 | Creator dashboard, agent create/edit, knowledge upload |
| 7 | MCP connections, settings, profile editing |
| 8 | APNs push, admin, guest mode, localization polish |
| 9 | Test coverage, migration/diff report, Definition-of-Done sign-off |

## Known limitations / TODO

- **Supabase SDK not yet imported.** `AuthService` is a placeholder that returns `.notImplemented` from `signIn`. Phase 2.
- **No chat streaming.** `APIClient` does request/response JSON only. Phase 4 will add an SSE client for `/api/v1/chat`.
- **StoreKit not wired.** Phase 5.
- **No offline cache.** All views hit the network. Phase 6+ may add lightweight disk caching.
- **English/i18n.** Japanese is primary; English strings will land in Phase 8 via a String Catalog.

## License

TBD — aligned with the upstream kabuto repo once chosen.
