# TestFlight Submission Checklist

For each RC build (`rc-X.Y.Z`). Run top-to-bottom; don't skip sections
out of order — later items assume earlier items passed.

## 0. Prerequisites (do once per account)

- [ ] Apple Developer Program membership is active
- [ ] App Store Connect app record created with the real Bundle ID
- [ ] App icon 1024×1024 uploaded (App Store Connect → App Information)
- [ ] App privacy disclosure filled in (Data not Linked to User: email,
      purchase history, identifiers; Data Linked: user ID)
- [ ] Three consumable IAP products registered and in "Ready to Submit":
      - `pt_500` — ¥500, localized name "500 pt"
      - `pt_1100` — ¥1,000, localized name "1,100 pt (+100 bonus)"
      - `pt_3500` — ¥3,000, localized name "3,500 pt (+500 bonus)"
- [ ] Sandbox tester account created (Users and Access → Sandbox)
- [ ] TestFlight internal testing group created with ≥1 internal tester

## 1. Source repository state

- [ ] `main` is at the intended commit (`git log --oneline -1`)
- [ ] `docs/migration-gaps.md` shows no unresolved **P0/P1** items
- [ ] No `TODO:` or `FIXME:` markers in new Phase 7 code
      (`grep -rn "TODO:\|FIXME:" KabutoiOS/Core KabutoiOS/Features`)
- [ ] RC tag cut and pushed:
      `git tag -a rc-X.Y.Z -m "RC X.Y.Z" && git push origin rc-X.Y.Z`

## 2. Build configuration

- [ ] `Config/Secrets.xcconfig` exists and every key from
      `docs/release-runbook.md#kabuto-ios` is populated (no `YOUR-*`
      placeholders)
- [ ] Bundle ID in `Config/Release.xcconfig` matches the App Store
      Connect app record
- [ ] Version string bumped: `MARKETING_VERSION` in
      `Config/Release.xcconfig` matches the RC tag minus the `rc-` prefix
- [ ] `CURRENT_PROJECT_VERSION` incremented (strictly > last TestFlight
      build number)
- [ ] Scheme is "KabutoiOS", configuration is "Release", destination is
      "Any iOS Device (arm64)"

## 3. Server side is ready

- [ ] kabuto production deploy matches the iOS RC's expected contract
      (same commit or newer, no breaking changes to `/api/v1/*`)
- [ ] `prisma migrate deploy` has been run on the production DB
      (run section 2 verification query from release-runbook)
- [ ] Every required env var from release-runbook section 1 is set in
      Vercel's production environment (not preview)
- [ ] `IAP_EXPECTED_BUNDLE_ID` matches the iOS build's Bundle ID exactly
- [ ] Supabase `agent-knowledge` bucket + RLS in place
      (release-runbook section 3)

## 4. Compile and unit tests

- [ ] `swift build --triple arm64-apple-ios17.0-simulator ...` is clean
      (0 errors, 0 warnings)
- [ ] All 41 iOS unit tests pass (`swift test` or Xcode ⌘U)
- [ ] kabuto standalone tests pass
      (`npx tsx src/lib/wallet/*.test.ts`, 26/26)

## 5. Archive

- [ ] Xcode → Product → Archive (Release, Any iOS Device)
- [ ] Archive size is sane (< 50MB for a Phase 7 IPA)
- [ ] Symbols are included (Build Settings → Debug Info Format:
      DWARF with dSYM)
- [ ] Bitcode is disabled (as of Xcode 14+ this is the only option)

## 6. Device smoke tests (real device, wired to the RC archive)

Use the sandbox Apple ID from section 0. Reset the simulator / fresh
install the IPA. Walk through every flow:

### Auth
- [ ] Sign up with a new email → confirmation email arrives → confirm →
      app shows signed-in state
- [ ] Sign out → returns to auth state
- [ ] Sign back in → session restored after cold launch

### Marketplace
- [ ] `/agents` loads within 2s on Wi-Fi
- [ ] Agent detail loads, shows description / starters / reviews
- [ ] Favorite toggle persists across reload
- [ ] Review submission works, appears in the list

### Chat (Phase 4/6.1)
- [ ] Tap "このエージェントと話す" → chat opens
- [ ] Send a message → assistant streams back
- [ ] Cancel mid-stream with "中断" → no leftover spinner, wallet NOT
      charged extra
- [ ] Force-quit the app and relaunch → prior conversation rehydrates
      (A11 restore path)
- [ ] Airplane mode during send → error appears gracefully,
      `ChatHistoryPersister` retries visible in Console logs

### Wallet + IAP (Phase 5)
- [ ] `/wallet` shows balance + recent purchases + usages
- [ ] Tap "500 pt" → sandbox purchase sheet → complete → balance
      increments by 500
- [ ] Force-quit after purchase but before the grant call returns →
      relaunch → balance is still credited exactly once (idempotency)
- [ ] Sandbox "deferred" transaction → observer backfills on next
      launch (tricky to simulate; StoreKit config file in Xcode can
      inject this)
- [ ] Retry a purchase with the same `idempotency_key` header manually
      via a proxy → response has `already_granted: true`, wallet not
      double-credited

### Creator (Phase 6 + 7)
- [ ] Create a new agent → appears in the list as DRAFT
- [ ] Edit the agent → instructions / starters / capabilities fields
      are **preloaded with the real values** (A7 regression)
- [ ] Save after editing → values persisted
- [ ] Upload a knowledge PDF → appears in the list (A8 happy path)
- [ ] Upload a 10MB file → rejected with "ファイルが大きすぎます"
- [ ] Upload a `.png` → rejected with "この形式のファイルはアップロードできません"
- [ ] Delete a knowledge document → disappears + no orphan blob in
      Supabase Storage
- [ ] Publish the agent → appears on the public `/agents` list

### Settings
- [ ] Profile edit: change name + bio + websiteUrl → saved
- [ ] MCP connection: add GitHub PAT → appears in the list
- [ ] MCP connection: swipe-to-delete → removed
- [ ] Google OAuth MCP (`google-drive`, `gmail`): tap "Google でログイン"
      → OAuth flow completes → banner appears

### Edge cases
- [ ] Japanese / English locale — all tab labels + empty states
      render correctly (Localizable.xcstrings ja/en)
- [ ] Dark mode — no unreadable color combinations
- [ ] Dynamic Type XXL — no clipped text
- [ ] VoiceOver on auth form — all inputs labeled

## 7. Upload to App Store Connect

- [ ] Xcode → Organizer → Distribute App → App Store Connect → Upload
- [ ] Wait for email "Your build is ready" (usually <15 minutes)
- [ ] Export compliance set to "Uses standard encryption only (HTTPS)"
- [ ] Review TestFlight build in App Store Connect:
      - Test Information: what to test notes in JA + EN
      - Encryption export compliance: already set above
      - Add internal testers

## 8. TestFlight hand-off

- [ ] Internal testers receive the build via TestFlight app
- [ ] Ship a short note summarizing what's in this RC
- [ ] Monitor TestFlight crash reports for 24h before promoting to
      external testers / App Store review
- [ ] Monitor Vercel logs for unusual `/api/v1/*` error rates
- [ ] Monitor Supabase DB for lock / timeout anomalies

## 9. Rollback plan

If a P0 bug is found:
1. **iOS side**: disable TestFlight distribution in App Store Connect
   → cut `rc-X.Y.(Z+1)` from a branch fixing the bug → re-run this
   checklist from section 3.
2. **Server side**: Vercel → Deployments → pick the previous green
   deploy → Promote to Production. `PointPurchase.source` migration is
   backward-safe (legacy code ignores the column).
3. **Data**: no manual DB intervention needed unless there was a bad
   wallet credit — in which case identify via
   `SELECT * FROM "PointPurchase" WHERE source='iap' AND "createdAt" > <bad-window>`
   and decide per-row whether to refund (delete the row + decrement
   wallet in one transaction).

## 10. Post-release

- [ ] Update `docs/migration-gaps.md` if any gap got resolved / added
      during the RC cycle
- [ ] Close the RC branch; merge any hotfixes back to `main`
- [ ] Tag the production release: `git tag v-X.Y.Z && git push origin v-X.Y.Z`
