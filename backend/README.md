# SpendSense API

Laravel backend for the SpendSense Flutter app. The app talks only to this
API; this API talks to Cloud Firestore.

```
Flutter app  ──►  Laravel API  ──►  Firestore
                       └──────────►  Gemini
```

## Why it's built this way

**Firestore over REST, not the official SDK.** Google's `google/cloud-firestore`
package talks gRPC, which needs a compiled PHP extension that is painful to
install on Windows. Firestore exposes every operation this app needs over
plain HTTPS, so `App\Services\FirestoreClient` uses that instead, with
`google/auth` (pure PHP) exchanging the service account for an access token.
No extensions to compile.

**Auth is verified locally.** The app sends its Firebase ID token as
`Authorization: Bearer <token>`. `VerifyFirebaseToken` checks the signature
against Google's published certificates (cached for a day), then checks the
audience and issuer so a token minted for a different Firebase project is
rejected. The account comes from the token's signature-checked subject and
**never from a URL**, so there is no path for one client to read another
account's data.

**One generic collection endpoint.** The Flutter client stores every domain
through a single generic `FirestoreCollection<T>`, with document shape known
only to that feature's repository. The backend mirrors that rather than
defining nine near-identical controllers, so adding a field to an entity
needs no backend change at all.

**Gemini is proxied.** The key used to ship inside the APK, where anyone can
unzip and read it. It now lives only in this server's `.env`.

## Setup

### 1. Requirements

PHP **8.4+** with `curl`, `mbstring`, `openssl` and `fileinfo` enabled, plus
Composer. (8.4 specifically: the locked Symfony 8.1 packages require
`>= 8.4.1`, so 8.3 cannot install this lockfile.) On Windows, a fresh PHP install also needs a CA bundle or every
outbound HTTPS call fails with `cURL error 60`:

```ini
; php.ini
extension_dir = "C:\path\to\php\ext"
curl.cainfo = "C:\path\to\php\extras\cacert.pem"   ; from https://curl.se/ca/cacert.pem
openssl.cafile = "C:\path\to\php\extras\cacert.pem"
```

### 2. Install

```bash
cd backend
composer install
cp .env.example .env
php artisan key:generate
```

### 3. Configure

In `.env`:

```
FIREBASE_PROJECT_ID=spendsense-dca63
GEMINI_API_KEY=your-key-here
GEMINI_MODEL=gemini-3.1-flash-lite
```

### 4. Service account

Firebase Console → ⚙️ Project settings → **Service accounts** →
**Generate new private key**. Save it as:

```
backend/storage/app/firebase/service-account.json
```

**This file is a real secret** — it grants full admin access to Firestore and
bypasses security rules. It is gitignored. Never commit or share it.
(`google-services.json` in the Flutter app is *not* a secret; this one is.)

### 5. Verify

```bash
php artisan firestore:smoke
```

Round-trips a throwaway document and asserts money stays an integer, booleans
stay booleans, nulls stay null, and nested receipt items survive. If this
passes, credentials and wire-format translation are both working.

### 6. Run

```bash
php artisan serve --host=0.0.0.0 --port=8000
```

`--host=0.0.0.0` matters: the default binds localhost only, which a phone
cannot reach.

## Endpoints

All under `/api/v1`, all requiring `Authorization: Bearer <firebase-id-token>`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | Liveness check (no auth) |
| POST | `/bootstrap` | Create any missing default categories |
| GET / PUT | `/profile` | User profile |
| GET | `/{collection}` | List |
| GET | `/{collection}/{id}` | Read one |
| PUT | `/{collection}/{id}` | Create or replace |
| DELETE | `/{collection}/{id}` | Delete |
| POST | `/ai/generate` | Gemini proxy |

Collections: `wallets`, `transactions`, `categories`, `budgets`,
`savings_goals`, `recurring_bills`, `receipts`, `reminders`, `ai_chat`.
Anything else is rejected.

`PUT` is create-or-replace because the client generates document ids (UUIDs)
before it ever calls, which also makes a retry after a dropped connection
safe. Replacement is deliberately full, not a merge: the app treats "field is
null" as real state for its undo and auto-contribute flows, so a cleared
field has to actually clear.

## Troubleshooting

**`cURL error 60` / `Could not verify credentials right now`** — no CA bundle;
see step 1. If you fixed `php.ini` while the server was running, restart it:
PHP reads its config at startup.

**`Invalid or expired token`** — the token is genuinely bad. Diagnose with:

```bash
php artisan firebase:verify-token <token>
```

which reports the audience, issuer, expiry and signature result individually
rather than a single 401.

**`Firebase service account not found`** — step 4, or the path in
`FIREBASE_CREDENTIALS` is wrong. Leave that variable blank to use the default
location.

**Phone can't connect** — the app must point at your machine's LAN IP, not
`localhost`, both devices must be on the same network, and Windows Firewall
must allow inbound TCP 8000. See the root README.
