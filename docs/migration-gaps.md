# Migration Gaps

Items where the iOS port had to make a decision that differs from the
current kabuto web app, or where a feature is intentionally deferred.
Each entry: **what**, **why**, **what we do instead**, **owner phase**.

## RC status snapshot (2026-04-19)

**Resolved, not blocking RC**: A1, A2, A3, A4, A5, A6, A7, A8, A11,
A12, A13, A14, A15, A16, A17, A18.

**Still open but not release-blocking**:
- **A9** — LLM tool calls (webSearch / image gen / runPython) execute
  server-side but aren't visualized in the iOS chat UI. Text answers
  still reflect tool results. Deferred.
- **A10** — Outbound multi-modal (image / file attachments from the
  user to the assistant). Phase 4 ships text-only. Deferred.
- **A12.1.1** — Automated monitor for apple.com/certificateauthority
  changes. Mitigated by the RC checklist reminder + `APPLE_ROOT_CA_PEM`
  env override path.
- **Guest chat** (A8 in older numbering) — iOS requires Bearer;
  web `/api/chat` still allows IP-based 3/day guest. On purpose.

**Release blockers**: none as of RC. Operator tasks remain (App Store
Connect products, prod DB migration apply) — see
`docs/release-runbook.md` §1 and §2.

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

## Phase 5

### A12. JWS signature verification on the IAP grant endpoint

**Current state**: `POST /api/v1/wallet/iap/grant` decodes the signed
StoreKit 2 transaction JWS **without verifying the cryptographic
signature**. It only:
  1. Splits the JWS into `header.payload.signature`
  2. Base64url-decodes the payload
  3. Parses as JSON
  4. Cross-checks `claims.transactionId` / `claims.productId` against
     the client-sent body (rejects mismatches)

The primary replay defense is the DB-level unique constraint on
`PointPurchase.stripeSessionId` (`iap_<transactionId>`). An attacker
who forges a JWS with a fresh, unused `transactionId` *could* currently
get a grant. This is acceptable for an internal/dev build but **MUST
be fixed before production**.

**Fix path**: implement full `JWSTransaction` verification using
Apple's root certificates and a JWS library (e.g. `jose` npm package).
Apple's `app-store-server-library` or the older `app-store-server-api`
clients handle the full chain validation + signature check. Alternative:
use Apple's `VerifyTransaction` endpoint in the App Store Server API,
sending the JWS and getting back a verified payload.

**Blocker**: requires Apple Developer account + App Store Connect
access to fetch the correct bundle ID and to register test products.

### A13. Reusing `PointPurchase.stripeSessionId` as the IAP idempotency key

**Current state**: to avoid a Prisma migration in Phase 5, we store
`iap_<transactionId>` in the existing `stripeSessionId` column (which
already has a unique constraint). The column name becomes a soft
misnomer on the IAP path.

**Why this is fine for now**: the column is a raw string, the
idempotency semantics work correctly, and the existing Stripe webhook
continues to use plain session IDs (`cs_*`) that never collide with
`iap_*`. The `source` in `/api/v1/wallet` response inspects this
prefix to label purchases `"iap"` vs `"stripe"`.

**Fix path**: when we next touch the schema, rename
`PointPurchase.stripeSessionId` → `idempotencyKey` and add an optional
`source` enum column. Pure migration, no logic change.

### A14. iOS Apple vs Web Stripe revenue split

**Status**: unresolved economics question, NOT a technical gap. Apple
takes 15–30% of IAP revenue; Stripe takes ~3.6% + ¥40 per transaction
for web. The existing `CREATOR_REVENUE_SHARE = 0.65` split is applied
**per chat usage**, not per purchase, so the creator's cut is the same
regardless of how the user topped up. For now the IAP grant just
credits the wallet at the advertised point amount — the platform eats
the Apple fee silently. Future pricing adjustments are a business
decision, not a code change.

### A15. StoreKit products unavailable → graceful fallback

**Current state**: `LiveStoreKitService.loadProducts()` stores the
resulting products, or an empty dictionary if Apple returns nothing /
the App Store Connect config is missing. `WalletView` then shows a
"現在購入不可" message and disables the buy buttons. This is what keeps
the app **building and running** without real App Store Connect
products registered — CI builds, sandbox dev without an account, etc.

### A16. App Store Connect setup (product registration)

**Before release**, the three placeholder product IDs
(`pt_500`, `pt_1100`, `pt_3500`) must be:
  1. Registered as consumable in-app purchases in App Store Connect
  2. Priced to match `expectedYen` in `WalletPackage.swift`
     / `amountYen` in `iap-packages.ts`
  3. Attached to a StoreKit configuration file in the Xcode project
     (optional but recommended for simulator testing)
  4. Submitted for review together with the app binary

This is a manual App Store Connect operation the user does once.
Documented separately in README build instructions when Phase 5 ships.

---

## Phase 6

### A12 (RESOLVED) — JWS signature verification

Phase 5's structural-only parser has been replaced by
`verifyIapJws` (`src/lib/wallet/iap-jws.ts`). The new path:

1. Parses the JWS protected header and extracts the x5c chain
2. Walks the chain as `X509Certificate` objects, verifying each cert's
   `notBefore` / `notAfter` and that each is signed by its issuer
3. Pins Apple Root CA - G3 (`src/lib/wallet/apple-root-ca.ts`) — any
   chain not rooted in this CA is rejected
4. Verifies the JWS signature against the leaf cert's public key via
   `jose.compactVerify`
5. Cross-checks `claims.bundleId` against `IAP_EXPECTED_BUNDLE_ID`
   (env) to reject tokens issued for other apps

Test coverage (`src/lib/wallet/iap-jws.test.ts`, 7/7 passing):
- happy path with a locally generated ES256 chain
- tampered payload → rejected
- wrong bundle id → rejected
- chain that doesn't chain to the pinned root (real Apple G3) → rejected
- expired cert (clock override) → rejected
- malformed fake JWS → rejected
- internally-consistent chain as a regression gate

**Still a gap**: Apple rotates its intermediate certs on a multi-year
cadence. If production verification starts failing after a rotation,
update the pinned PEM in `apple-root-ca.ts` with the new file from
apple.com/certificateauthority. Tracked as **A12.1**.

### A11 (RESOLVED) — iOS chat persistence

Phase 4 left iOS-sent chat turns unsaved. Phase 6 adds:

- Server: `saveChatMessagesForUser` core extracted from the existing
  cookie-based action (signature unchanged for web). New
  `POST /api/v1/chat-history/save` route wraps it for Bearer callers.
- iOS: `ChatViewModel.onFinishedPersist` hook fires after every
  successful stream with the full message list. `ChatView` wires it to
  `ChatHistoryRepository.save` so the iOS turns show up in
  `GET /api/v1/chat-history` immediately.
- Test: `ChatPersistenceTests` covers (a) full message list delivered on
  success, (b) hook NOT called on stream failure.

### A17. Creator editor shows list-only fields, not full detail

**Current state**: `AgentEditorView` edit mode is seeded from the
`/api/v1/creator/agents` list row, which does NOT include
`systemPrompt` / `instructions` / `toolConfig`. So when editing an
existing agent, the "指示プロンプト" field starts empty and the creator
has to retype it if they want to change it — hitting save without
retyping would wipe the existing instructions.

**Why not fetch the full detail**: would need a new
`GET /api/v1/creator/agents/:slug` endpoint that returns the full
`Agent` row (not just the public-visible `/api/v1/agents/:slug`).
Trivial to add, but requires a new route + another query round-trip
when opening the editor.

**Phase 7 fix**: add `GET /api/v1/creator/agents/:slug` and have
`AgentEditorView.applyMode` load the full payload before the user
can edit. Until then the editor is safe for CREATE and risky for
EDIT — document the caveat in the editor header string.

### A18. Knowledge upload (pre-signed URL flow)

**Status**: deferred to Phase 7. The user direction called for a
kabuto-mediated pre-signed URL flow (NOT direct Supabase Storage from
iOS), but implementing it requires:
- A Supabase Storage signed-URL generator endpoint
  (`POST /api/v1/creator/agents/:slug/knowledge/upload-url`) that
  reuses the existing `attachKnowledgeFilesFromForm` helper
- A companion register endpoint
  (`POST /api/v1/creator/agents/:slug/knowledge/register`) that
  creates the `KnowledgeDocument` row after iOS uploads
- iOS file picker + multipart upload
- Tests for the signed-URL round-trip

This is a self-contained sub-feature (~200 lines + tests) that fits
naturally in Phase 7 alongside the A17 editor fix. For now, creators
must upload knowledge files from the web editor.

### A13 (STATUS) — billing-integrity schema migration

Still intentionally deferred. Phase 6 does not add the
`source` column to `PointPurchase` because the current
`iap_<transactionId>` prefix scheme on `stripeSessionId` is
functionally equivalent for idempotency (which IS the billing
integrity concern). The rename is cosmetic and can wait for Phase 7's
schema-change window.

**Risk acknowledged**: none for correctness — the fast-path
`findUnique` + fallback `catch P2002` combination is race-safe.

---

## Phase 7 (release polish)

### A7 (RESOLVED) — Creator edit form preload

Server: `GET /api/v1/creator/agents/:slug` now returns the full editor
payload (systemPrompt→instructions, starters, knowledgeDocuments,
capabilities/actions/mcp flattened via editor-config, mcpServices, tags).

iOS: `AgentEditorView.applyMode` fetches the detail on entry and seeds
the form. Edit mode no longer silently wipes instructions on save.

### A8 (RESOLVED) — Knowledge upload

Server endpoints (Bearer-gated, owner check on every call):
- `POST /api/v1/creator/agents/:slug/knowledge/upload-url` —
  validates mime (pdf/txt/md/csv/json) + size (≤8MB) + file count
  (≤8 per agent), returns a short-lived Supabase Storage signed URL
  scoped to `<userId>/<agentId>/`
- `POST /api/v1/creator/agents/:slug/knowledge/register` —
  verifies the storage_key prefix, creates the KnowledgeDocument row
- `DELETE /api/v1/creator/agents/:slug/knowledge/:documentId` —
  removes the blob + DB row

iOS: `KnowledgeUploader` implements the three-step flow with bounded
retries per hop. UX integrated in `AgentEditorView` via `.fileImporter`.

### A12.1 (RESOLVED) — Rotation-friendly root CA config

`src/lib/wallet/apple-root-ca.ts` now exports a trusted-roots array +
`getAppleTrustedRootsPem()`. Adding a new Apple root is:
1. Paste the PEM into `APPLE_TRUSTED_ROOTS`
2. Update the file's fingerprint comment
3. Deploy

Emergency rotation without deploy: `APPLE_ROOT_CA_PEM` env var.

`verifyIapJwsTyped` walks the chain against each trusted root and
accepts the first match. Single-root back-compat preserved via the
still-exported `APPLE_ROOT_CA_G3_PEM` constant.

### A13 (RESOLVED, pending migration) — PointPurchase.source column

Prisma schema now has `source String?` on `PointPurchase` + `@@index`.
New migration file (20260417180000_point_purchase_source) is
**additive only** — no backfill, no destructive changes. Must be
applied in production via `npx prisma migrate deploy` before the
Phase 7 server binary runs, but the API is backward-compatible (reads
fall back to the `stripeSessionId` prefix heuristic if `source` is
null, so legacy rows keep working).

New writes populate source='iap' (via grantIapCore) or
source='idem_marker' (via the client-idem marker row).

### A12.1.1 — Root CA monitoring (still deferred)

We still don't have an automated watcher for
apple.com/certificateauthority/ changes. Current mitigation: the RC
checklist reminds the operator to verify the baked-in G3 PEM hasn't
been replaced upstream. Acceptable for Phase 7 RC; revisit when we
have a build pipeline that can periodically fetch and diff.

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

Added in Phase 5:

- [x] `GET /api/v1/wallet` — balance + 10 recent purchases + 10 recent
      usages
- [x] `GET /api/v1/wallet/history?cursor=&limit=&kind=` — merged
      time-ordered feed of PointPurchase + WalletTransaction
- [x] `POST /api/v1/wallet/iap/grant` — validates body + JWS structure,
      delegates to `grantIapCore` with DB-level idempotency

Added in Phase 6:

- [x] `POST /api/v1/chat-history/save` — persist iOS chat turns (A11)
- [x] `PATCH /api/v1/me/profile` — profile editor
- [x] `GET/POST/DELETE /api/v1/mcp/connections[/:serverKey]` — MCP CRUD
- [x] `GET/POST /api/v1/creator/agents` — creator list + create
- [x] `PATCH/POST /api/v1/creator/agents/:slug` — edit + publish toggle
- [x] `verifyIapJws` cryptographic verification (A12 resolved)

Still needed (Phase 7+):

- [ ] `GET /api/v1/creator/agents/:slug` — full detail for edit form (A17)
- [ ] `POST /api/v1/creator/agents/:slug/knowledge/upload-url` +
      companion register (A18)
