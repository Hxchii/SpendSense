# SpendSense

A personal finance tracker for Android, built with Flutter. It does the usual
wallet/transaction/budget tracking, plus two AI features powered by Gemini:

- **Receipt scanner** — photograph a receipt and it extracts the merchant,
  line items, and total, suggests a category, and flags likely duplicates.
- **Financial assistant** — a chat that can answer questions about your
  spending *and* act on your behalf (log an expense, create a budget, set up
  a recurring bill) by proposing an action you confirm before it's written.

Data lives in Cloud Firestore, scoped per account.

---

## Getting it running

### 1. Prerequisites

- Flutter **3.44.7** or newer (Dart SDK `^3.12.2`)
- Android SDK with `cmdline-tools` installed and licenses accepted
  (`flutter doctor --android-licenses`)
- JDK 17

Run `flutter doctor` and clear anything it complains about before continuing.

### 2. Clone and install packages

```bash
git clone https://github.com/Hxchii/SpendSense.git
cd SpendSense
flutter pub get
```

### 3. Add your Gemini API key

Both AI features call the Gemini API directly, using a key passed in at build
time. The key is **not** in this repo.

Create `env.json` in the project root (it's gitignored — copy the shape from
`env.example.json`):

```json
{
  "GEMINI_API_KEY": "your-key-here"
}
```

Get a key from [Google AI Studio](https://aistudio.google.com/apikey). The
free tier is enough for development.

> The app still builds and runs without a key — the AI screens just report
> themselves as unavailable rather than crashing.

### 4. Firebase

`android/app/google-services.json` and `lib/firebase_options.dart` are
committed, so the app connects to the existing Firebase project out of the
box. Nothing to do.

<details>
<summary>Pointing it at your own Firebase project instead</summary>

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
flutterfire configure --project=your-project-id --platforms=android
```

Then in the Firebase console:
- **Firestore Database** → create one
- **Authentication → Sign-in method** → enable **Anonymous**

Deploy the security rules so accounts stay isolated:

```bash
firebase deploy --only firestore:rules
```
</details>

### 5. Run it

```bash
flutter run --dart-define-from-file=env.json
```

The `--dart-define-from-file` flag is required — without it the AI features
have no key. Same when building:

```bash
# Debug APK — bigger, but real stack traces when something breaks
flutter build apk --debug --dart-define-from-file=env.json

# Release APKs, split per CPU architecture (install the arm64-v8a one)
flutter build apk --release --split-per-abi --dart-define-from-file=env.json
```

Output lands in `build/app/outputs/flutter-apk/`.

---

## How the code is organised

Each feature owns a vertical slice, and every layer within it points inward:

```
lib/features/<feature>/
  domain/          entities + repository interfaces (pure Dart, no Flutter)
  data/
    firestore/     Firestore implementation of the interface
    remote/        HTTP calls (the two Gemini repositories)
  application/     Riverpod providers + controllers
  presentation/    screens and widgets
```

Two rules keep it swappable:

1. `domain/` never imports `data/`.
2. `application/<feature>_providers.dart` is the **only** file that names a
   concrete implementation. Swapping Firestore for a REST backend later means
   editing one line per feature, not rewriting screens.

`lib/core/` holds the shared pieces: theming, routing, the Firestore helper,
notifications, and small utilities.

### Decisions worth knowing about

**Money is stored as integer minor units** (centavos), never floating point —
`Money(15050)` is ₱150.50. Floats lose cents to rounding, and this is a
finance app.

**IDs are client-generated UUIDs**, not Firestore auto-IDs, so an entity has
its identity before it's ever written.

**Anonymous authentication.** There's no login screen; the app signs in
anonymously on first launch to get a stable UID. Firestore needs an identity
to scope and secure data, but this is a personal on-device tracker, so a
password would be friction with no benefit. The tradeoff: uninstalling the
app loses the account and its data.

**Data is namespaced per account** under `users/{uid}/...`, and
`firestore.rules` enforces that a user can only touch their own subtree.

**Sorting and filtering happen in Dart**, not in Firestore queries. Result
sets here are small, and it avoids needing a composite index for every screen.

**Derived values are never stored.** Wallet balances, budget progress, and
goal progress are computed from transactions on every read, so they can't
drift out of sync with the underlying data.

### Gemini integration

Both AI repositories call Gemini directly from the client and share a few
patterns:

- **Structured output.** The receipt scanner uses `responseMimeType:
  application/json` with a `responseSchema`, so parsing can't fail on prose.
  The assistant uses function calling with declared tool schemas.
- **Grounded in real data.** The model only ever picks from category and
  wallet lists read fresh from the repositories, so it can't invent an ID.
- **Nothing is written without confirmation.** The assistant *proposes* an
  action; the app resolves the names against what actually exists and writes
  it only after the user taps confirm.
- **Today's date is injected into the prompt.** A model has no idea what day
  it is and will otherwise answer "due today" with a date from its training
  data. Past dates are additionally clamped in code.
- **Low-confidence scans are rejected.** Below 90% confidence, or when the
  model reports a quality problem (blurry, cropped, glare, too dark), the user
  is asked to retake the photo rather than shown a wrong total they'd likely
  accept.

---

## Notifications

Three alerts are implemented and fire while the app is running or on launch:

| Alert | Trigger |
|---|---|
| Budget alerts | A budget crosses 80%, and again when it goes over |
| Bill reminders | A recurring bill is due or gets auto-paid |
| Savings goal reminders | Progress nudges and auto-contributions |

Permission is requested during onboarding, from the "Get Started" tap — a real
user gesture, which is what the OS requires.

**Known limitation:** these are not true scheduled background notifications.
The app can't wake itself at 9 AM while closed; that needs a scheduled server
job (a paid Firebase plan) or Android WorkManager. Weekly/monthly summary
notifications were removed rather than shipped as switches that do nothing.

---

## Tech stack

| | |
|---|---|
| Framework | Flutter 3.44 |
| State | Riverpod 2.6 |
| Routing | go_router |
| Backend | Firebase (Cloud Firestore + Anonymous Auth) |
| AI | Gemini (`gemini-3.1-flash-lite`) |
| Charts | fl_chart |
| Other | camera, image_picker, local_auth, flutter_secure_storage, flutter_local_notifications, pdf, csv, share_plus |

---

## Troubleshooting

**Gradle daemon crashes with an out-of-memory error.** The JVM heap sizes in
`android/gradle.properties` are tuned for a 16 GB machine. Gradle, Kotlin, and
the Android resource tools each run in their own JVM, so the limits are
deliberately conservative — lower them further if you have less RAM, and note
that *raising* them usually makes it worse.

**`IllegalArgumentException: this and base files have different roots`.**
Kotlin's incremental compiler can't compute relative paths across Windows
drive letters (project on `D:`, pub cache on `C:`). `kotlin.incremental=false`
in `android/gradle.properties` works around it.

**AI features say "not configured".** `env.json` is missing, or you built
without `--dart-define-from-file=env.json`.
