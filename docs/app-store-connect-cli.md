# App Store Connect CLI

This repo now includes a lightweight App Store Connect API CLI so we can inspect apps and subscriptions from the terminal instead of relying on browser clicks for every debugging pass.

The script lives at `scripts/app_store_connect_cli.rb` and uses only the Ruby standard library that already ships on macOS.

## What this helps with

- find an app by bundle ID
- list subscription groups for an app
- list subscription products and their App Store Connect states
- inspect subscription localizations
- fetch raw App Store Connect API endpoints when we need more detail

This is especially useful when a paywall says subscription products are unavailable, because we can quickly confirm whether App Store Connect is returning the products and what state they are in.

## What this does not replace

Some checks still need the Apple web UI:

- `Agreements, Tax, and Banking`
- Apple Developer `Certificates, Identifiers & Profiles` capability toggles
- creating the App Store Connect API key the first time

The goal is to minimize browser work, not pretend the browser never exists.

## Setup

1. In App Store Connect, create an API key with access to the app you want to inspect.
2. Download the `.p8` key file and store it somewhere local outside git.
3. Copy the example env file:

```bash
cp Config/Environment/app_store_connect.env.example Config/Environment/app_store_connect.env
```

4. Fill in:

- `ASC_ISSUER_ID`
- `ASC_KEY_ID`
- `ASC_PRIVATE_KEY_PATH`

5. Keep the real env file local only. `.gitignore` already excludes the real env file and `.p8` keys.

## Commands

List apps visible to the API key:

```bash
ruby scripts/app_store_connect_cli.rb apps
```

Find one app by bundle ID:

```bash
ruby scripts/app_store_connect_cli.rb apps --bundle-id com.skinlit.SkinLit
```

List subscription groups and products:

```bash
ruby scripts/app_store_connect_cli.rb subscriptions --bundle-id com.skinlit.SkinLit
```

Run a quick subscription health check:

```bash
ruby scripts/app_store_connect_cli.rb doctor --bundle-id com.skinlit.SkinLit
```

Fetch a raw endpoint:

```bash
ruby scripts/app_store_connect_cli.rb raw /v1/apps
```

Use a custom local env file:

```bash
ruby scripts/app_store_connect_cli.rb --env-file /path/to/app_store_connect.env doctor --bundle-id com.skinlit.SkinLit
```

Print JSON instead of formatted output:

```bash
ruby scripts/app_store_connect_cli.rb doctor --bundle-id com.skinlit.SkinLit --json
```

## Recommended workflow when subscriptions do not load

Run this first:

```bash
ruby scripts/app_store_connect_cli.rb doctor --bundle-id com.skinlit.SkinLit
```

Look for:

- no subscription groups
- subscriptions not in `APPROVED`
- missing localizations
- obvious mismatches between expected product IDs and the products returned by Apple

If the CLI shows healthy products but the app still loads none, the next suspects are:

- paid apps agreement / tax / banking
- storefront availability
- in-app purchase capability/signing
- recent App Store Connect edits still propagating

Apple notes that sandbox changes can take up to one hour to appear.

## Notes for future apps

- Reuse the same script in sibling apps if you keep the same workspace conventions.
- The only app-specific input you need for inspection is the bundle ID.
- If you want a shared workspace-level version later, move this script into a common tooling repo and keep the env contract the same.

## Official references

- [App Store Connect API overview](https://developer.apple.com/documentation/appstoreconnectapi)
- [Automate your workflow with the App Store Connect API](https://developer.apple.com/app-store-connect/api/)
- [Subscriptions API](https://developer.apple.com/documentation/appstoreconnectapi/subscriptions)
- [Subscription Groups API](https://developer.apple.com/documentation/appstoreconnectapi/subscription-groups)
- [TN3186: Troubleshooting In-App Purchases availability in the sandbox](https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox)
- [TN3188: Troubleshooting In-App Purchases availability in the App Store](https://developer.apple.com/documentation/technotes/tn3188-troubleshooting-in-app-purchases-availability-in-the-app-store)
