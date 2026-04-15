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

Still needed (Phase 3+):

- [ ] `GET /api/v1/agents` — paginated marketplace list (wraps
      `getMarketplaceAgents`)
- [ ] `GET /api/v1/agents/:slug` — wraps the existing detail query
- [ ] `POST /api/v1/chat` — probably just re-exports the existing
      `/api/chat` handler with Bearer auth instead of cookies
- [ ] `POST /api/v1/agents/:slug/reviews` — wraps `submitAgentReview`
- [ ] `POST /api/v1/wallet/iap/grant` — new; validates a StoreKit
      transaction server-side and credits the wallet (replaces the Stripe
      webhook path for iOS)
