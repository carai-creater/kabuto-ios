# Migration Gaps

Items where the iOS port had to make a decision that differs from the
current kabuto web app, or where a feature is intentionally deferred.
Each entry: **what**, **why**, **what we do instead**, **owner phase**.

---

## Phase 2

### A1. Demo login mode (`NEXT_PUBLIC_ENABLE_DEMO_LOGIN` / `kabuto_uid` cookie)

**Web behavior**: `/api/auth/demo` sets a signed cookie `kabuto_uid`, and
`getSessionUserId()` falls back to it when no Supabase session exists. This
is gated by `NEXT_PUBLIC_ENABLE_DEMO_LOGIN` and used in development /
screenshot recording.

**Why we can't 1:1 port it**: iOS doesn't share cookies with the web app,
and writing a random user id into Keychain bypasses Supabase Auth — there's
no Bearer token to send to `/api/v1/*`.

**Phase 2 fallback**: In `#if DEBUG` builds only, `AuthView` shows a
"デモ用の値を入れる" button that pre-fills the email/password fields with a
fixed demo account (`demo@kabuto.local`). The user still signs in through
Supabase normally — the demo account just needs to exist in the Supabase
project. In Release builds the button is compiled out entirely.

**Follow-up**: decide whether to (a) create a shared `demo@kabuto.local`
user in the production Supabase project and ship real credentials via
xcconfig, or (b) add a server-side `/api/v1/auth/demo` that mints a fresh
anonymous Supabase session. Either way the cookie mechanism is not coming
back to iOS.

### A2. OAuth providers (Google, etc.)

**Web behavior**: currently not wired in the repo — `src/app/actions/auth-login.ts`
only does email/password. No `signInWithOAuth` calls found.

**iOS stance**: also not wired in Phase 2. If web adds OAuth later,
iOS will mirror via `supabase-swift`'s `signInWithOAuth(provider:)` which
needs `ASWebAuthenticationSession` and a redirect URL — requires a custom
URL scheme registration in `Info.plist`.

### A3. Session cookie refresh via middleware

**Web behavior**: `src/middleware.ts` calls `updateSession()` on every
request and rewrites `sb-*` cookies. This is how tokens are silently
refreshed.

**iOS stance**: `supabase-swift` auto-refreshes access tokens using the
refresh token. `AuthService` subscribes to `authStateChanges` and mirrors
refreshed tokens into `SessionStore`. No middleware equivalent needed —
but token expiration is now driven by the SDK, not a Next.js hop, so
any server logic that assumes "tokens are refreshed on every request"
must rely on the Bearer being fresh at call time (which it is).

---

---

## Phase 3

### A4. Anonymous browsing

**Web behavior**: `/` and `/agents` are publicly browsable. Only dashboard
routes are gated by middleware.

**iOS Phase 2 behavior**: the whole app was gated — `signedOut` forced
`AuthView`. Phase 3 relaxes this so the `MainTabs` view renders for both
`signedOut` and `signedIn`. Writes (favorite, review) call
`AppEnvironment.requireAuth()`, which either no-ops (if already signed in)
or presents `AuthView` as a sheet and returns false.

**Why not a "local favorites" shim**: confirmed out of scope — per user
direction we don't carry a local-only favorite state that would later need
migration into the server.

### A5. `convertFromSnakeCase` decoder strategy

**What changed**: `APIClient`'s default decoder used to be
`.convertFromSnakeCase` (with `.convertToSnakeCase` on the encoder).
Combined with our models' explicit `CodingKeys` (needed for `icon_emoji`,
`price_per_use_pt`, etc.) this caused key-not-found errors at runtime —
the strategy rewrote server keys to camelCase before the explicit
`rawValue = "icon_emoji"` lookup. Fixed by removing the strategy; all
domain models now own their wire naming explicitly. Caught by the new
`AgentRepositoryTests.testListBuildsQueryStringAndDecodesItems` test, not
by unit decode tests in isolation.

### A6. Cursor pagination / list totals

**Status**: the Phase 3 `GET /api/v1/agents` endpoint is **not paginated**
— it returns up to 50 items from the already-cached `getMarketplaceAgents`.
The web app doesn't paginate either. Fine for now; revisit when the agent
count grows past a few hundred. (`limit` is clamped to ≤100 in the route
and accepted but unused as a cursor.)

### A7. Creator-only detail view

**Status**: `GET /api/v1/agents/:slug` does look up non-published agents
when the Bearer-resolved user is the creator, matching the web's existing
`isPublished: true OR creatorId: sessionUserId` behavior. But the iOS
`AgentDetailView` does not yet visually distinguish "published" vs "draft"
state or expose creator-only edit affordances — that's a Phase 6 (creator
dashboard) concern.

---

## Phase 4

### A8. Guest chat (3/day IP limit)

**Web behavior**: unauthenticated users can chat with published agents
up to 3 times per day, rate-limited via `tryConsumeGuestChatSlot` using a
hashed client IP (`guest-rate-limit.ts`).

**iOS Phase 4 stance**: **not implemented.** `/api/v1/chat` rejects
unauthenticated requests with 401. iOS users must sign in to chat.
`AppEnvironment.requireAuth()` is triggered automatically when the view
model reports `.unauthorized`.

**Why**: the IP-hash approach doesn't transfer to a mobile client (NAT
collisions, shared carrier proxies). DeviceCheck / App Attest + a
server-side device-id-based rate limit is the correct replacement and is
deferred. `/api/chat` (web) still runs the existing guest path unchanged.

### A9. Tool calls, image generation, code interpreter in chat UI

**Web behavior**: the chat handler exposes `searchKnowledge`, `webSearch`,
`generateImage`, `runPython` tools. The web UI renders tool invocations
inline with expandable sections.

**iOS Phase 4 stance**: the backend tools are **still active** because
Phase 4 uses the same `processChatRequest` pipeline, so the LLM can and
will call them. But the iOS `ChatView` **only renders text parts** —
tool invocation events (`tool-input-available`, `tool-result`,
`reasoning-delta`, etc.) are silently dropped by `SSEDecoder`. From the
user's perspective the tools still work (the assistant's text output
reflects their results), they just aren't visualized.

Deferred to Phase 7 or later, when we can design UI for:
- Tool call cards ("searching web: ...", collapsible results)
- Inline image attachments from `generate-image`
- Code blocks + output from `runPython`

### A10. Multi-modal messages (images, files, reasoning)

**Web behavior**: Vercel AI SDK supports parts of type `file`, `image`,
`reasoning`, etc. The web UI renders them.

**iOS Phase 4 stance**: outbound messages are text-only. The
`RequestBody.UIMessage.Part` encoder sends a single `{ type: "text", text }`
part. Incoming text-delta events are the only content rendered.

### A11. ChatSession persistence on iOS send

**Web behavior**: the web chat UI calls `saveChatMessages` after each
turn to persist the conversation to `ChatSession` / `ChatMessage` tables.
The iOS POST to `/api/v1/chat` does **not** persist — the server side
streamText pipeline charges the wallet but doesn't write the user's
turn into the DB.

**Consequence**: `GET /api/v1/chat-history` will return what `/api/chat`
(web) saved, but **not** what iOS sent in Phase 4. After an iOS user
exits and relaunches, their previous conversation is empty unless they
also used the web app.

**Fix path**: add a server-side persistence step inside
`processChatRequest`'s `onFinish` callback (or a dedicated iOS-only
`saveChatMessagesForUser` adapter called from the iOS `send` flow).
Deferred to a Phase 4.x patch after initial live testing confirms the
rest of the flow works.

---

## Deferred to later phases (placeholders)

| # | Gap | Target phase |
|---|-----|--------------|
| B1 | Chat streaming / SSE client for `/api/chat` | Phase 4 |
| B2 | StoreKit In-App Purchase in place of Stripe Checkout | Phase 5 |
| B3 | Knowledge file upload (Supabase Storage from iOS) | Phase 6 |
| B4 | MCP credential storage UI | Phase 7 |
| B5 | APNs push in place of Web Push + VAPID | Phase 8 |
| B6 | Guest chat rate limit (IP-based) — probably moved to device-ID-based | Phase 8 |
| B7 | Stripe webhook → wallet crediting. Does NOT apply to iOS (StoreKit path), but the backend must learn to accept StoreKit receipts | Phase 5 (backend) |
| B8 | English localization strings in a String Catalog | Phase 8 |

---

## Backend endpoints still to add

These belong to kabuto, not kabuto-ios, and should be **thin adapters**
over existing logic. Already added in Phase 2:

- [x] `GET /api/v1/me` — wraps `ensurePrismaUserFromAuth` + a select
- [x] `src/lib/auth/verify-bearer-token.ts` — Bearer JWT → Prisma user id

Added in Phase 3:

- [x] `GET /api/v1/home` — aggregated home (recommended / hot / new +
      wallet / recent / favorites for authed users)
- [x] `GET /api/v1/agents` — list wrapping `getMarketplaceAgents`, with
      in-memory `q` / `tag` / `sort` / `limit`
- [x] `GET /api/v1/agents/:slug` — detail + reviews (top 20), respects
      `isPublished: true OR viewer is creator`
- [x] `POST /api/v1/agents/:slug/reviews` — wraps new `submitReviewCore`
- [x] `POST / DELETE /api/v1/agents/:slug/favorite` — wraps new
      `toggleFavoriteCore`

Added in Phase 4:

- [x] `POST /api/v1/chat` — thin wrapper around the shared
      `processChatRequest` with `allowGuest: false`
- [x] `GET /api/v1/chat-history` — wraps new `getLatestChatSessionForUser`

Still needed (Phase 5+):

- [ ] `POST /api/v1/wallet/iap/grant` — new; validates a StoreKit
      transaction server-side and credits the wallet (replaces the Stripe
      webhook path for iOS) (Phase 5)
- [ ] iOS-side `saveChatMessages` equivalent or server-side persistence
      inside `processChatRequest.onFinish` (see A11)
