Fill these values before shipping:

- `GOOGLE_CLIENT_ID`
- `GOOGLE_REVERSED_CLIENT_ID`
- `SKIN_ANALYSIS_API_ENDPOINT`
- `APP_SHARE_URL` (`https://skinlit.lat` for launch referrals and legal pages)

Note: in `.xcconfig` files, literal `//` starts a comment. Write URLs using the Xcode-safe
`https:/$()/host` form instead of a raw `https://host` literal.
- `DEVELOPER_MODE` (`YES` to force guest/dev onboarding mode, `NO` for normal behavior)
- `APP_MODE` (`production` in release, `dev` in debug)
- `UNLIMITED_SCANS_MODE` (`YES` only when you intentionally want no scan cap, `NO` for normal testing and release)
- `REFERRALS_ENABLED` (`YES` only when the production referral backend routes are deployed, `NO` to hide invite/claim flows in the app)

For App Store Connect CLI inspection:

- copy `Config/Environment/app_store_connect.env.example` to `Config/Environment/app_store_connect.env`
- fill `ASC_ISSUER_ID`, `ASC_KEY_ID`, and `ASC_PRIVATE_KEY_PATH`
- run `ruby scripts/app_store_connect_cli.rb doctor --bundle-id com.skinlit.SkinLit`
- full usage is documented in `docs/app-store-connect-cli.md`
- `bundle exec fastlane ...` now auto-loads the same local env file, so the CLI and fastlane share one credential source

Launch readiness automation:

- run `./scripts/release_verification.sh` for Release build + simulator test verification
- run `./scripts/validate_docs_site.sh` for docs packaging, AASA validation, and public URL checks
- run `./scripts/submission_doctor.sh` for the end-to-end local readiness pass
- if you use fastlane, prefer `bundle exec fastlane ios readiness_doctor`

Recommended:

- keep `Debug.xcconfig` and `Release.xcconfig` tracked
- fill `Base.xcconfig` locally for development
- replace values with production-safe identifiers before archiving
- keep `Resources/SkinScore.entitlements` aligned with `APP_SHARE_URL` and include `applinks:skinlit.lat`
