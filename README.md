# kabuto-ios

Native iOS (SwiftUI) client for [kabuto](https://github.com/carai-creater/kabuto) — the Japanese AI-agent marketplace.

This project mirrors the feature set of the existing Next.js web app without changing its behavior or domain model. The existing Next.js backend is the source of truth; this app talks to it via a new `/api/v1/*` REST layer (to be added in kabuto).

## Status

### Phase 1 (foundation) — done

- [x] Xcode project (filesystem-synchronized groups)
- [x] SwiftUI `@main` + root `TabView`
- [x] `AppEnvironment` DI container
- [x] `AppConfig` loading from Info.plist (injected via xcconfig — no hardcoded secrets)
- [x] `APIClient` skeleton (URLSession, bearer-token provider hook)
- [x] Feature placeholders for Home / Marketplace / Wallet / Profile

### Phase 2 (auth + session) — done

- [x] `supabase-swift` 2.43.1 wired as a package dependency
- [x] `AuthService` implementation (signIn / signUp / signOut / restore / auto-refresh via `authStateChanges`)
- [x] `SessionStore` persistence in Keychain (`KeychainStoring` protocol, in-memory stub for tests)
- [x] Login/Signup UI with email+password, validation, error display
- [x] `#if DEBUG` demo credentials button (compiled out in Release)
- [x] `/api/v1/me` client repository
- [x] `GET /api/v1/me` on kabuto side — thin adapter over existing `ensurePrismaUserFromAuth`
- [x] Unit tests: `AppConfig` × 3, `SessionStore` × 3

### Phase 6 (creator + profile/MCP + chat persistence + JWS verification) — done

- [x] A11: iOS chat turns are persisted after every successful stream
      via new `POST /api/v1/chat-history/save` — `ChatViewModel` fires
      `onFinishedPersist` with the full message list, `ChatView` wires
      it to `ChatHistoryRepository.save`
- [x] A12: `verifyIapJws` cryptographically verifies the StoreKit 2
      signed transaction. Apple Root CA - G3 is pinned
      (`src/lib/wallet/apple-root-ca.ts`). Chain walk + leaf signature
      via `jose.compactVerify`. Bundle id pinning via
      `IAP_EXPECTED_BUNDLE_ID`.
- [x] A (creator): `CreatorRepository` (list / create / update / publish),
      `CreatorDashboardView` (list + DRAFT badge + swipe-to-publish),
      `AgentEditorView` (minimal editor: icon, title, description,
      instructions, starters, price)
- [x] B (settings): `ProfileEditView`, `McpConnectionsView` (+ add sheet),
      wired from `ProfileView` when signed in
- [x] Server thin wrappers: `/api/v1/creator/agents[/:slug]`,
      `/api/v1/me/profile`, `/api/v1/mcp/connections[/:serverKey]`,
      all delegating to existing cores
- [x] Tests: `ChatPersistenceTests` × 2 + `iap-jws.test.ts` × 7
      (real ECDSA-P256 chain generation in-process)

### Phase 5 (wallet + StoreKit IAP) — done

- [x] `WalletPackage` catalog (`pt_500`, `pt_1100`, `pt_3500`)
- [x] `StoreKitServicing` protocol + `LiveStoreKitService` (StoreKit 2,
      `Product.products(for:)`, `product.purchase()`, `Transaction.updates`)
- [x] `WalletRepository` (+ `WalletReading` protocol): fetchWallet,
      fetchHistory (cursor), grantIAP
- [x] `WalletViewModel` (`@Observable @MainActor`): refresh, pagination,
      purchase flow, observer-driven backfill for deferred transactions
- [x] `WalletView` rewritten: balance card, purchase buttons with
      real `displayPrice`, history list with "もっと見る", graceful
      "現在購入不可" fallback when products aren't registered yet
- [x] kabuto side: `GET /api/v1/wallet`, `GET /api/v1/wallet/history`,
      `POST /api/v1/wallet/iap/grant`
- [x] kabuto `grantIapCore`: DB-level idempotency via the existing
      `PointPurchase.stripeSessionId` unique constraint
      (`iap_<transactionId>` encoding — no migration needed)
- [x] kabuto standalone test runner (`npx tsx`) for
      `iap-grant.test.ts`: 7 cases
- [x] iOS tests: `WalletViewModelTests` × 5

### Phase 4 (chat streaming) — done

- [x] `SSEDecoder` parses the Vercel AI SDK v6 UI message stream
      (`text-start`, `text-delta`, `text-end`, `finish`, `[DONE]`, `error`).
      Tool invocations / reasoning / data parts are silently dropped for
      now.
- [x] `SSEClient` drives `URLSession.bytes(for:)` and surfaces
      `ChatStreamEvent`s via `AsyncThrowingStream`. HTTP 401 → `.notAuthorized`,
      402 → `.insufficientBalance(required/balance)`, other → `.http`.
- [x] `ChatRepository` (`ChatStreaming` protocol) for history + streaming
      sends. iOS sends text-only `UIMessage` parts.
- [x] `ChatViewModel` (`@Observable @MainActor`): send / cancel / stream
      deltas, state machine (`idle / loadingHistory / sending / failed / unauthorized`).
- [x] `ChatView`: message bubbles, composer, conversation starters,
      toolbar "中断" during streaming, auto-scroll to latest.
- [x] `AgentDetailView` → `ChatView` navigation via `NavigationLink`.
- [x] kabuto side: `POST /api/v1/chat` + `GET /api/v1/chat-history`.
      Both reuse existing logic via `processChatRequest` and
      `getLatestChatSessionForUser` extracts. Web `/api/chat` unchanged
      (still cookie-based, still allows guest).
- [x] Tests: `SSEDecoderTests` × 8, `ChatViewModelTests` × 4 (happy
      path, unauthorized, http error, cancel).

### Phase 3 (marketplace + reviews + favorites + home) — done

- [x] `Agent` / `AgentDetail` / `HomePayload` Codable domain models
- [x] `AgentRepository` (list / detail / setFavorite / submitReview)
- [x] `HomeRepository` (single aggregated `/api/v1/home` call)
- [x] `MarketplaceView` — search bar, sort menu (usage / new / rating), debounced reload
- [x] `AgentDetailView` — hero, description, conversation starters, reviews, favorite toggle
- [x] `ReviewSheet` — 1-5 star rating + comment, submit flow
- [x] `HomeView` rewritten — recommended / hot / new + (signed-in) wallet / recent / favorites
- [x] **Anonymous browsing** — `RootView` shows `MainTabs` for both `signedOut` and `signedIn`; writes call `env.requireAuth()` which presents `AuthView` as a sheet
- [x] kabuto side: `GET /api/v1/home`, `GET /api/v1/agents`, `GET /api/v1/agents/:slug`, `POST /api/v1/agents/:slug/reviews`, `POST|DELETE /api/v1/agents/:slug/favorite`
- [x] kabuto refactor: `review-core` / `favorite-core` extracted; existing server actions delegate unchanged
- [x] `agent-serializer` normalizes snake_case JSON + Decimal handling
- [x] Fix: `APIClient` no longer uses `.convertFromSnakeCase` (conflicted with explicit `CodingKeys`)
- [x] Tests: `AgentDecodingTests` × 4, `AgentRepositoryTests` × 4 (URL/query/method/body via `MockURLProtocol`)

### Not yet

- [ ] Creator dashboard / MCP settings / profile editing — Phase 6
- [ ] StoreKit IAP — Phase 5
- [ ] Creator dashboard — Phase 6
- [ ] MCP / settings / profile editing — Phase 7
- [ ] APNs push / admin / guest / localization — Phase 8

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
