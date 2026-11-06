# Sorted

**Say it once.** Sorted is an AI life assistant. You type or say one sentence, such as "call mom Sunday evening, renew car insurance before March 10, and get milk, eggs and dish soap", and it turns that into reminders, deadlines, bills and shopping lists that are already scheduled.

> **Status:** planning. This repository holds the folder structure and this README. No code has been written yet.

- MVP spec: [Life Assistant App — MVP Spec](https://claude.ai/artifact/X5bi4nu17cCguRTK3wdjUr)
- Mockups, post images and logo: [App Mockups for Launch Post](https://claude.ai/artifact/6YVqNxKFDi5W5vdSTnYDB7)

Both links are private to the owner until they are shared from the page's Share menu.

## What it does

| Feature | What the user gets | Release |
| --- | --- | --- |
| **Say it once** | One sentence in, structured items out: reminders, deadlines, tasks, bills, groceries. Nothing saves until the user confirms. | MVP |
| **Smart reminders** | Natural-language times ("every last Friday", "3 days before") with reliable alerts. | MVP |
| **Today** | Daily tasks plus an AI daily brief of what matters today. | MVP |
| **Bills & subscriptions** | What's due, what's going out in the next 30 days, autopay flags. | MVP |
| **Shopping lists** | Items grouped by aisle, added from any sentence. | MVP |
| **Assistant** | Chat that knows your bills, tasks and lists: "Anything I'm forgetting this week?" | MVP |
| **Heads up** | A morning check for free trials about to charge, bills that went up, and things running low. | MVP+ |
| **Family** | Shared households: shared lists, chores, bills and reminders. | v1.1 |

**Pricing:** freemium. The free tier covers the core features. A paid plan unlocks advanced AI and family features. The first 100 founding members get $19.99/yr for life.

## Platforms

| Platform | Folder | Stack | Notes |
| --- | --- | --- | --- |
| iOS | `apps/ios` | Swift, SwiftUI (iOS 18+), SwiftData cache, StoreKit 2 | Local notifications in a rolling window, because iOS caps pending notifications at 64 |
| Android | `apps/android` | Kotlin, Jetpack Compose, Room cache, Google Play Billing | Exact alarms and WorkManager for reminders |
| PWA | `apps/pwa` | TypeScript, React, Vite, service worker | The full app in the browser. Installable on desktop and Android. Web Push for reminders. Stripe for payments |
| Website | `apps/web` | TypeScript, Astro (static) | Marketing site, waitlist, founding-member offer, legal pages. Fast and SEO-friendly |
| Backend | `backend/` | Supabase: Postgres, Auth, Edge Functions, Storage, pg_cron | One backend serves every client |

The mobile apps are native on purpose: reminders and notifications are the product, and native code gives the most reliable scheduling on each OS. The two web apps share TypeScript packages. All clients share one API contract.

## Architecture

```
   iOS app        Android app        PWA           Website
   (SwiftUI)      (Compose)          (React)       (Astro)
       \              |                 |              |
        \             |                 |         waitlist only
         +------------+-----------------+--------------+
                              |
                    Supabase (backend/)
        +---------------------+----------------------+
        |                     |                      |
   Postgres + RLS       Edge Functions          pg_cron jobs
   (data per household) parse · assistant ·     daily brief ·
                        insights · notify ·     insights ·
                        billing-webhooks        push fan-out
                              |
                     Claude API (server side only)
```

- **AI runs only on the server.** Clients never hold an API key. Edge Functions call Claude with structured outputs, so `parse` always returns valid JSON that matches the shared schemas.
  - The default model is `claude-opus-5-5` at low effort.
  - Evaluate `claude-haiku-5-5` for `parse`, to cut cost.
- **Data is scoped by household.** Every table carries `household_id`, and row-level security enforces it. Family sharing in v1.1 then needs no schema rewrite.
- **Offline first on mobile.** The apps write to a local cache and sync to Postgres. Reminders still fire with no network.
- **One subscription across all stores.** App Store, Google Play and Stripe purchases all land in a single `entitlements` table, through `billing-webhooks`.

## Repository layout

```
sorted/
├── README.md
├── apps/
│   ├── ios/                  Native iOS app (Xcode project, SwiftUI)
│   ├── android/              Native Android app (Gradle, Kotlin, Compose)
│   ├── pwa/                  Installable web app, the full product in a browser
│   └── web/                  Marketing website and waitlist
├── backend/
│   └── supabase/
│       ├── migrations/       SQL migrations: tables, RLS policies, indexes, cron jobs
│       ├── seed/             Sample data for local development (the March 2026 demo data)
│       ├── tests/            Database and RLS policy tests
│       └── functions/        Edge Functions (Deno + TypeScript)
│           ├── _shared/      Shared helpers: auth, Claude client, schemas, errors
│           ├── parse/        Sentence in, structured items out ("Say it once")
│           ├── assistant/    Chat that reads the user's bills, tasks and lists
│           ├── insights/     "Heads up" checks: trials, price rises, running low
│           ├── daily-brief/  The AI daily brief on the Today screen
│           ├── notify/       Push delivery: APNs, FCM and Web Push
│           └── billing-webhooks/  App Store, Google Play and Stripe events, into entitlements
├── packages/                 Shared code for the TypeScript apps and the backend
│   ├── contracts/            API contract: OpenAPI spec and JSON Schemas. Source of truth for every client
│   ├── api-client/           Typed TypeScript client generated from contracts/
│   ├── design-tokens/        Colors, type, spacing and radii, exported to CSS, Swift and Kotlin
│   └── web-ui/               Shared React components for pwa/ and web/
├── design/
│   ├── brand/                Logo, app icon (1024×1024), wordmark
│   ├── mockups/              App screen designs
│   └── marketing/            Post images for Reddit and X
├── docs/
│   └── decisions/            Architecture decision records (ADRs), one file per decision
├── scripts/                  Dev scripts: setup, codegen, release
└── .github/
    └── workflows/            CI: lint, test and build for every app and the backend
```

Empty folders contain a `.gitkeep` file so that git keeps them.

### How the shared pieces connect

- **`packages/contracts`** defines every request and response once.
  - The TypeScript client is generated from it.
  - The Swift and Kotlin models are generated from it.
  - The Edge Functions validate against it.
  - A change to the API starts here.
- **`packages/design-tokens`** holds the brand in one place: accent `#5856D6`, the type scale and the corner radii. It exports CSS variables for the web, a Swift file for iOS and a Kotlin file for Android, so all four clients look like one product.

## Roadmap

1. **Foundations:** set up the Supabase project, write the schema and RLS, add Auth (Sign in with Apple, Google, email magic link), and write `contracts/` and `design-tokens/`.
2. **Website and waitlist:** ship `apps/web` with the waitlist and the founding-member offer, so feedback and signups start before the app exists.
3. **Core AI:** build the `parse` Edge Function and an eval set of real sentences. Measure accuracy and cost per call.
4. **iOS MVP:** Say it once, Today, Bills, Lists and Assistant. Then a TestFlight beta.
5. **PWA:** the same features in the browser, with Web Push.
6. **Android:** a feature-parity build, then a Play Store closed test.
7. **Heads up and daily brief:** add scheduled AI jobs with pg_cron.
8. **v1.1 Family:** households, invites, shared lists and bills.

## Open decisions

Record each choice in `docs/decisions/` once it's made.

- **Subscriptions:** RevenueCat, or our own `billing-webhooks` reading App Store Server Notifications, Google RTDN and Stripe webhooks directly.
- **Monorepo tooling for the TypeScript parts:** pnpm workspaces with Turborepo is the likely choice.
- **Analytics and crash reporting:** for example PostHog and Sentry.
- **Domain and app IDs:** the bundle ID, package name and web domain.
- **Pricing details:** the free-tier limits and the monthly vs yearly price.

## Getting started

There's nothing to run yet. Setup steps for each app will go here as code lands.
