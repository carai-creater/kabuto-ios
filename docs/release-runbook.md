# Release Runbook (RC → Production)

One page. If something breaks in production, start here.

Target reader: on-call engineer.
Audience prerequisite: admin access to Vercel (kabuto), Supabase, Apple
Developer portal, App Store Connect, and the kabuto-ios repo.

---

## 1. Required environment variables (production)

### kabuto (Next.js, set in Vercel → Environment Variables)

| Key | Required | Used by | Notes |
|---|:-:|---|---|
| `DATABASE_URL` | ✅ | Prisma | Supabase transaction pooler `:6543`, pooled |
| `DIRECT_URL` | ✅ | Prisma migrations | Supabase direct `:5432` |
| `NEXT_PUBLIC_SUPABASE_URL` | ✅ | Supabase SSR + iOS | e.g. `https://xxx.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | ✅ | Supabase SSR | prefer publishable over anon |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` |  | fallback | only if publishable key absent |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY` |  | 2nd fallback | legacy Vercel template placeholder; leave unset in new deploys |
| `SUPABASE_SERVICE_ROLE_KEY` | ✅ | Storage signed URLs, auth.getUser(token) | server-side only — never exposed |
| `SUPABASE_URL` |  | fallback | only if `NEXT_PUBLIC_SUPABASE_URL` absent |
| `MCP_CREDENTIAL_KEY` | ✅ | MCP token encryption at rest | 32+ random bytes base64 |
| `NEXT_PUBLIC_SITE_URL` | ✅ | Supabase redirects, email links | canonical `https://kabuto.example.com` |
| `VERCEL_URL` |  | auto-set by Vercel | fallback if `NEXT_PUBLIC_SITE_URL` absent |
| `GUEST_IP_HASH_SALT` | ✅ | `/api/chat` guest rate limit | 32+ random bytes |
| `NEXT_PUBLIC_ENABLE_DEMO_LOGIN` |  | demo mode | **must be unset/false in production** |
| `DEMO_WALLET_MIN_BALANCE_PT` |  | demo mode | `0` in production |
| `OPENAI_API_KEY` | ✅ | GPT-4o etc | |
| `ANTHROPIC_API_KEY` | ✅ | Claude | |
| `GOOGLE_GENERATIVE_AI_API_KEY` | ✅ | Gemini | `GEMINI_API_KEY` also accepted |
| `BRAVE_SEARCH_API_KEY` |  | `webSearch` tool | `BRAVE_API_KEY` also accepted; missing ⇒ tool falls back to "unavailable" text |
| `STRIPE_SECRET_KEY` | ✅ | `/api/stripe/*` (web only) | live key for prod |
| `STRIPE_WEBHOOK_SECRET` | ✅ | webhook signature verify | |
| `IAP_EXPECTED_BUNDLE_ID` | ✅ | `/api/v1/wallet/iap/grant` JWS bundle pin | must match the shipped app's Bundle ID |
| `APPLE_ROOT_CA_PEM` |  | Apple root override | leave unset to use baked-in G3 |
| `GOOGLE_OAUTH_CLIENT_ID` | ✅ (if using Google MCP) | `/api/mcp/oauth/google/*` | |
| `GOOGLE_OAUTH_CLIENT_SECRET` | ✅ (if using Google MCP) | same | |
| `NEXT_PUBLIC_VAPID_PUBLIC_KEY` | ✅ | Web push subscribe (web only) | |
| `VAPID_PRIVATE_KEY` | ✅ | Web push send | |
| `VAPID_SUBJECT` | ✅ | `mailto:ops@...` | |
| `CREATOR_REVENUE_SHARE` |  | usage billing split | default `0.65` |
| `WALLET_PROMO_PT` |  | promo bonus | default `1000` |
| `WALLET_PROMO_SLUG` |  | promo id | default `ltd-1000pt-202604` |
| `KABUTO_VECTOR_RPC_ENABLED` |  | knowledge search | `true` to enable pgvector RPC |
| `KABUTO_VECTOR_MATCH_RPC` |  | RPC function name | default `match_knowledge_chunks` |
| `CRON_SECRET` |  | future cron jobs | not used yet but reserved |
| `NODE_ENV` |  | runtime switch | Vercel sets to `production` |

### kabuto-ios (Release scheme, `Config/Secrets.xcconfig`, gitignored)

| Key | Required | Notes |
|---|:-:|---|
| `KABUTO_API_BASE_URL` | ✅ | `https://<prod>.vercel.app` (no trailing slash; `//` escaped as `/$()/`) |
| `KABUTO_SUPABASE_URL` | ✅ | Same project as the server |
| `KABUTO_SUPABASE_ANON_KEY` | ✅ | Publishable key |

**Hard rule:** before archiving a Release build, diff the xcconfig
against `Secrets.example.xcconfig` and verify every non-comment line has
been replaced with a real value.

---

## 2. Pre-deploy database work (one-off)

Run exactly once per environment before shipping the Phase 7 server:

```sh
npx prisma migrate deploy         # applies 20260417180000_point_purchase_source
npx prisma generate               # regenerates the client
```

Verification query (should succeed after deploy):

```sql
SELECT column_name, is_nullable, data_type
  FROM information_schema.columns
 WHERE table_name = 'PointPurchase' AND column_name = 'source';
-- expect: source | YES | text
```

---

## 3. Supabase infrastructure checklist

| Item | Required | Verification |
|---|:-:|---|
| `agent-knowledge` Storage bucket exists | ✅ | dashboard → Storage → bucket list |
| RLS on `storage.objects` allows `service_role` to INSERT / SELECT / DELETE in `agent-knowledge/<userId>/<agentId>/` | ✅ | dashboard → SQL → `SELECT policyname FROM pg_policies WHERE tablename='objects'` |
| `avatars` bucket exists | ✅ | user avatars |
| Database backup cadence ≥ daily | ✅ | Supabase project → backups |
| `pgvector` extension enabled (if knowledge search in use) | conditional | `SELECT extname FROM pg_extension WHERE extname='vector'` |

---

## 4. Incident runbook — IAP / chat / knowledge

### 🔴 IAP grant failing in production

**Symptoms**
- iOS users report "購入に失敗しました" after completing a sandbox/prod purchase
- `/api/v1/wallet/iap/grant` 4xx or 5xx rate spikes in logs

**First 5 minutes**
1. Check Vercel logs for `scope:"api.v1.wallet.iap.grant"` JSON entries.
   Look at the `event` and `reason` fields.
2. If `event: "verify_failed"` with `reason: "chain_invalid"` dominates
   → Apple rotated a root CA. **Mitigation:**
   set `APPLE_ROOT_CA_PEM` env to the new root PEM bundle from
   apple.com/certificateauthority and redeploy. No code change needed.
3. If `event: "verify_failed"` with `reason: "bundle_mismatch"` →
   `IAP_EXPECTED_BUNDLE_ID` env is wrong. Fix and redeploy.
4. If `event: "grant_failed"` with `code: "wallet_missing"` → the user's
   wallet row wasn't created by Supabase sign-up. Rare race — manual
   backfill: `INSERT INTO "Wallet" ("id","userId","balancePt","updatedAt") VALUES (cuid(), <userId>, 0, now());`
5. If 5xx from Stripe/Supabase → see "dependency outage" below.

**Rollback**
- Revert to the previous deploy (Vercel → Deployments → prior green deploy → Promote to Production).
- The `PointPurchase.source` column is additive and non-breaking, so a
  rollback works even if you've already `migrate deploy`d. Legacy code
  ignores the column.
- StoreKit will redeliver unfinished transactions on the next iOS launch,
  so no manual reconciliation needed — once the server recovers, the
  iOS `Transaction.updates` observer re-grants automatically.

**Never do**
- Do NOT manually `UPDATE "Wallet" SET "balancePt"` to credit a lost grant.
  Always replay through `/api/v1/wallet/iap/grant` with the original JWS
  (idempotency will prevent double grant).

---

### 🟠 Chat streaming broken

**Symptoms**
- iOS users see "通信エラー" in chat / stream hangs / empty assistant bubbles
- `/api/v1/chat` 5xx rate spikes

**First 5 minutes**
1. Check Vercel logs: is it OpenAI/Anthropic/Gemini returning errors?
2. Verify API keys haven't rotated / been rate-limited.
3. If one provider is down, `getLanguageModel(modelId)` will error for
   that provider only — users can switch model in the UI as a workaround.
4. If persistence is the only broken part (chat works, but history
   doesn't save on restart): look for
   `ChatHistoryPersister` log lines — `chat-history save exhausted`
   means the server's `/api/v1/chat-history/save` is 5xx'ing.

**Rollback**
- Chat is served by `/api/chat` (web) and `/api/v1/chat` (iOS), both of
  which call the same `processChatRequest`. A bad deploy rolls back
  cleanly via Vercel → Promote prior deploy.
- Chat history persistence is best-effort; a failed save does NOT charge
  the user extra — wallet charging happens inside the streamText
  `onFinish` callback, independent of the history save.

---

### 🟡 Knowledge upload failing

**Symptoms**
- Creators see "アップロードに失敗" / "アップロード URL の発行に失敗"
- `/api/v1/creator/agents/:slug/knowledge/*` 5xx

**First 5 minutes**
1. `reason: "storage_not_configured"` → `SUPABASE_SERVICE_ROLE_KEY` or
   `NEXT_PUBLIC_SUPABASE_URL` missing.
2. `reason: "signed_url_failed"` → Supabase Storage is down or the
   `agent-knowledge` bucket is missing. Check Supabase status.
3. HTTP PUT directly to the signed URL failing → Supabase Storage
   outage; iOS will retry automatically (2 retries + 500/1000 ms
   backoff). If sustained, disable the upload UI feature flag (future
   work) and communicate to creators.

**Rollback**
- Knowledge upload is an additive feature. Disabling it by hiding the
  iOS file picker (requires a new app version) is the fallback.
- **No data corruption risk**: if a blob uploads but registration fails,
  the blob is orphaned in Storage — run the orphan sweep script
  (Phase 7.x future work) or manually `DELETE FROM storage.objects
  WHERE bucket_id='agent-knowledge' AND created_at < now() - '7 days'
  AND NOT EXISTS (SELECT 1 FROM "KnowledgeDocument" kd WHERE kd."storageKey" = name);`

---

### ⚫ Dependency outage (Supabase / Vercel / OpenAI)

- Vercel down → check status.vercel.com. Cannot mitigate from our side.
- Supabase auth down → users can't sign in; existing Keychain sessions
  keep working until refresh. Existing Bearer tokens keep working
  against `/api/v1/*` for up to 1 hour.
- Supabase DB down → all /api/v1 read endpoints fail. No iOS-side cache
  yet (Phase 8+). Communicate via a static banner on `/` if possible.
- OpenAI/Anthropic/Gemini down → partial — other providers still work.
  Users can switch models.

---

## 5. Post-incident checklist

- [ ] Add a postmortem note to `docs/postmortems/YYYY-MM-DD.md`
- [ ] If a root CA rotated: bump `APPLE_TRUSTED_ROOTS` in code in the
      next release so `APPLE_ROOT_CA_PEM` can be unset
- [ ] If a new env var was needed: add it to Section 1 of this runbook
- [ ] If a migration was needed: add a `prisma/migrations/<ts>_*`
      directory + append a row to Section 2
