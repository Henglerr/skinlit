# SkinLit App Store Submission

## Review Notes

Use this text in App Store Connect review notes:

SkinLit provides cosmetic skin-scoring feedback from a user-submitted selfie and is not intended for medical diagnosis. The app works without sign-in by creating a local-only profile on device for onboarding, scan history, and skin journey data. Sign in with Apple or Google is optional and appears only when the user chooses to activate Cloud Save Beta for online sync and referral features. Selfies are sent to our backend for cosmetic AI analysis, and the app may also store a processed preview locally so history views can display past scans. Home > Delete Local Data removes the local-only profile and associated on-device data. Home > Delete Account removes a signed-in cloud account and associated stored data. If the user has an active subscription, the deletion flow explains that Apple billing continues until the user cancels it in App Store subscriptions.

## Pre-Submission Checklist

- Set real `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` in the production xcconfig inputs.
- Confirm `SKIN_ANALYSIS_API_ENDPOINT` points to the production backend.
- Set backend Sign in with Apple revocation envs:
  - `APPLE_TEAM_ID`
  - `APPLE_KEY_ID`
  - `APPLE_PRIVATE_KEY`
  - `ADMIN_SECRET`
- Verify the backend supports:
  - `/v1/referrals`
  - `/v1/referrals/invite`
  - `/v1/referrals/claim`
  - `/v1/referrals/rewards`
  - account deletion with Sign in with Apple token revocation when applicable
- Host `skinlit.lat` with:
  - `/privacy/`
  - `/terms/`
  - `/support/`
  - `/referral/`
  - `/404.html`
  - a valid `/.well-known/apple-app-site-association` file for the production app bundle identifier
- Align App Store Connect privacy answers with cloud selfie upload, on-device processed selfie previews, and cosmetic AI analysis.
- Verify live In-App Purchase products:
  - `com.skinlit.pro.weekly`
  - `com.skinlit.pro.monthly`
  - `com.skinlit.pro.yearly`

## TestFlight Smoke Test

- Launch the app and complete onboarding without signing in.
- Sign in with Apple.
- Sign in with Google.
- Open an invite link on a device with the app installed.
- Open an invite link on a device without the app installed and manually claim the code after sign-in.
- Complete the first-scan consent flow and receive a result.
- Purchase and restore subscriptions.
- Delete local-only data as a guest user.
- Delete an account with and without an active subscription.
