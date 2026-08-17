# SpendSense — Frontend Build Plan

**Scope of this plan:** Flutter mobile app (Android & iOS), offline-first. Backend (AI proxy) is owned by a teammate — this plan lays the groundwork (API contract + mock layer) but does not implement a server.

**Context:** Personal/portfolio-quality build, phased milestones, AI features powered by Google Gemini (called through a backend your teammate builds).

---

## 1. Tech Stack (proposed — confirm in review)

| Concern | Choice | Why |
|---|---|---|
| State management | Riverpod | Compile-safe DI, great async/stream support, easy to mock repositories for the AI layer |
| Local database | Drift (SQLite) | Type-safe SQL, real relations (wallets↔transactions↔budgets), solid migration story for an evolving schema |
| Routing | go_router | Declarative, supports the auth/PIN-gate redirect pattern cleanly |
| Charts | fl_chart | Category breakdowns, income vs. expense trends |
| Camera | `camera` package | Full control over the receipt capture UI |
| App lock | `local_auth` + `flutter_secure_storage` | Biometric + PIN, secure storage for the PIN hash |
| Notifications | `flutter_local_notifications` | Budget alerts, bill reminders, weekly/monthly summaries — all offline |
| Export | `csv` / `pdf` packages | Local backup/export, no backend needed |

**Not needed:** on-device OCR (ML Kit). Since receipt scanning goes through Gemini vision on the backend, sending the photo and getting structured JSON back is simpler and more accurate than parsing on-device text. (Docs hedge offline OCR as "if supported" — treat as a future stretch, not V1.)

---

## 2. Local Data Model (Drift tables)

- **user_profile** (single row): displayName, currency, monthlyIncome, monthlyBudget, financialGoal, themeMode, appLockType, onboardingComplete
- **wallets**: name, type (cash/bank/e-wallet/credit), balance, icon/color, archived
- **categories**: name, type (income/expense), icon, color, isDefault
- **transactions**: walletId, categoryId, type, amount, date, note, source (manual/receipt/recurring), receiptId
- **budgets**: categoryId, walletId (nullable = all wallets), period, limitAmount, rollover
- **savings_goals**: name, targetAmount, currentAmount, targetDate, status
- **recurring_bills**: name, categoryId, amount, frequency, nextDueDate, reminderDaysBefore, autoLogTransaction
- **receipts**: imagePath, parsedJson, merchant, date, subtotal, tax, discount, total, suggestedCategoryId, status, duplicateOfReceiptId
- **reminders**: type (budget_alert/bill_reminder/goal_reminder/weekly_summary/monthly_report), scheduledFor, delivered, read
- **ai_chat_messages**: role, content, createdAt — persisted locally so chat history survives offline

---

## 3. Backend Contract (hand this to your teammate)

**Backend framework: Laravel (professor-mandated).** The contract below is framework-agnostic REST/JSON, so it maps cleanly onto Laravel — your teammate implements it as standard Laravel API routes/controllers. Since the app is single-user/local, propose keeping auth minimal: Laravel Sanctum's simple personal-access-token flow is the natural fit (issue one token per app install, sent as `Authorization: Bearer <token>`) rather than the full Passport OAuth2 flow, which is overkill here. The frontend just needs a stable place to plug in whatever token scheme they land on.

```
POST /v1/ai/chat
  body: { message, history: [{role, content}], financialContext: { currency, totals, budgets, goals, periodLabel } }
  → { reply, suggestions?: string[] }

POST /v1/ai/receipt-scan   (multipart image)
  → { merchant, date, items: [{name, qty, price}], subtotal, tax, discount, total,
      suggestedCategory, currency, duplicateHash, confidence }

GET  /v1/health
  → 200 OK   (lets the app show an "AI unavailable" banner instead of failing silently)

Errors: { error: { code, message } }  (consistent shape for all endpoints)
```

**Privacy-by-default:** `financialContext` sent to `/ai/chat` is an aggregated snapshot (totals, category sums, budget status) — never a raw transaction dump. Matches the doc's privacy emphasis and keeps the AI payload small.

**Mocking strategy:** Define `AiAssistantRepository` / `ReceiptScanRepository` as abstract interfaces. Build a `FakeAiAssistantRepository` (canned responses + simulated latency) for all of Phase 3–4 development, and a `HttpAiAssistantRepository` that matches the contract above. Swap via a Riverpod provider override or `--dart-define=USE_MOCK_AI=true`. This means AI features are fully demoable before the backend exists, and swapping to the real thing later is a one-line change.

---

## 4. Phased Roadmap

**Phase 0 — Foundation**
Project scaffold (feature-first folders), design tokens + light/dark/system theme, Drift setup + migrations, Riverpod app shell, go_router with auth-gate redirect, reusable widget kit (buttons, cards, inputs).
*Exit: navigable empty-state app, theme switch works, DB initialized.*

**Phase 1 — Onboarding + Core Tracking (MVP)**
Onboarding flow (profile, currency, goal picker, notification prefs, optional PIN/biometric), wallets CRUD, categories (seeded + custom), manual income/expense entry with history/filters, dashboard, category budgets with progress tracking.
*Exit: a user can fully track finances manually, offline, end to end — demoable on its own.*

**Phase 2 — Reports, Goals, Bills, Security**
Charts (category breakdown, income vs. expense trend), savings goals with progress, recurring bills/subscriptions with due-date reminders, all local notifications, PIN/biometric app lock, CSV/PDF export.
*Exit: full non-AI feature set from the spec, secured.*

**Phase 3 — AI Receipt Scanner**
Camera capture + preview, upload to `/ai/receipt-scan` (mocked), review/edit screen before saving as a transaction, duplicate-receipt warning, offline queueing/messaging.
*Exit: snap-a-receipt-to-transaction flow works against mock data.*

**Phase 4 — AI Financial Assistant**
Chat UI with quick-question chips, local chat history, financial-context snapshot builder, mocked responses.
*Exit: conversational assistant demo works end-to-end against mock, ready to point at the real backend.*

**Phase 5 — Polish & Handoff**
Empty/loading/error states, accessibility pass, list/DB performance pass, swap mock repositories for real HTTP ones once backend is ready, app icon/branding.
*Exit: release-candidate build.*

---

## 5. Non-Functional Requirements

- **Offline resilience:** every screen works with no network except the two AI screens, which must show a clear "needs internet" state rather than failing silently.
- **Testing:** widget tests per feature for CRUD flows at minimum.
- **Accessibility:** dynamic text scaling, adequate contrast in both themes.

---

## 6. Open Questions / Assumptions to Confirm

I made calls on a few implementation details to keep moving rather than ask a second round of questions — flag any you want changed:

1. **State/DB stack:** Riverpod + Drift — fine, or do you/your team already use Bloc, GetX, Isar, or Hive elsewhere?
2. **Design source:** any existing Figma/mockups to build to, or should Phase 0 include a from-scratch UI design pass?
3. **Currency:** assumed single currency set once at onboarding (matches the doc's singular "Preferred Currency" field), not per-wallet multi-currency with conversion. Confirm?
4. **Export formats:** CSV, PDF, or both?
5. **AI auth scheme:** proposed Sanctum bearer token above — confirm with your teammate once they start the Laravel side.
6. **Min OS targets:** any constraints on minimum Android/iOS versions from your dev environment?
7. **Other professor requirements:** is MySQL/another DB mandated for the Laravel side, and are there required deliverables (ERD, SRS, defense/presentation format, specific SDLC methodology) that should shape how this plan is documented?
