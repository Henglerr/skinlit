# SkinLit Legal Pages and Referral Landing

This folder contains the public pages used by the SkinLit iOS app and the Cloudflare-hosted referral flow:

- `privacy/index.html`
- `terms/index.html`
- `support/index.html`
- `referral/index.html`
- `r/404.html` referral fallback for `/r/<code>`
- `.well-known/apple-app-site-association` for universal links
- `_headers` so Cloudflare serves the AASA file as JSON

## Publish steps

1. From the repo root, run:

   ```bash
   ./scripts/package_docs_site.sh
   ```

2. Upload the generated `skinlit-pages.zip` to Cloudflare Pages using Direct Upload.
3. Do not drag visible files out of Finder one by one. That flow can omit hidden paths like `.well-known/`.
4. Attach the custom domain `skinlit.lat`.
5. Confirm these URLs resolve publicly:
   - `https://skinlit.lat/privacy`
   - `https://skinlit.lat/terms`
   - `https://skinlit.lat/support`
   - `https://skinlit.lat/referral/?code=ABC123`
   - `https://skinlit.lat/.well-known/apple-app-site-association`

## Validation commands

Use the dedicated validator when you want both the local archive check and the public-site check:

```bash
./scripts/validate_docs_site.sh
```

Useful flags:

- `--skip-package` if `skinlit-pages.zip` is already current
- `--skip-remote` if you only want the local archive/AASA validation
- `--base-url https://staging.example.com` to validate a non-production deployment

## Pre-upload checks

- `unzip -l skinlit-pages.zip | grep '.well-known/apple-app-site-association'`
- `unzip -l skinlit-pages.zip | grep '_headers'`
- `curl -I https://skinlit.lat/.well-known/apple-app-site-association`

Expected base URL:

`https://skinlit.lat/`

Final links:

- `https://skinlit.lat/privacy`
- `https://skinlit.lat/terms`
- `https://skinlit.lat/support`
- `https://skinlit.lat/referral`

Referral behavior:

- Installed users should open universal links like `https://skinlit.lat/referral/?code=ABC123` directly in the app.
- Users without the app should land on `/referral/?code=ABC123` and see the manual claim flow immediately.
- `referral/index.html` shows the code and explains how to claim it manually after install and sign-in.
