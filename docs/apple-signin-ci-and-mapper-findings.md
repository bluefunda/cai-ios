# Apple Sign In — CI Archive Failure & Mapper Findings

## 1. CI Archive Failure — Provisioning Profile Missing Sign In with Apple

### What broke

Merging PR #82 (v1.2.0 release) triggered the `ios-deploy` CI job, which failed at the **Archive** step:

```
error: Provisioning profile "***" doesn't include the Sign In with Apple capability.
error: Provisioning profile "***" doesn't include the com.apple.developer.applesignin entitlement.
```

The distribution provisioning profile stored in the GitHub secret `APPLE_PROVISIONING_PROFILE` was generated **before** native Sign In with Apple was added to the app. It does not include the `com.apple.developer.applesignin` entitlement.

### What exists on the dev machine

| File | Location | Notes |
|------|----------|-------|
| `BlueFunda_AI_App_Store.mobileprovision` | `~/Downloads/` | Outdated — missing Sign In with Apple |
| `Certificates.p12` | `~/Downloads/` | Distribution cert — valid |
| `AuthKey_3Z5Y3Q79HF.p8` | `~/Downloads/` | App Store Connect API key |
| `Apple Distribution: BlueFunda, Inc. (UR7HWT72SR)` | Keychain | Distribution cert installed |

### Fix

Log into **developer.apple.com** with `devops@bluefunda.com`:

1. **Identifiers** → `com.bluefunda.ai` → Capabilities → ensure **Sign In with Apple** is checked → Save
2. **Profiles** → find the App Store distribution profile for `com.bluefunda.ai` → Edit → Regenerate → Download
3. Base64-encode and update the GitHub secret:
   ```bash
   base64 -i ~/Downloads/<new-profile>.mobileprovision | pbcopy
   # Paste into: GitHub → Settings → Secrets → APPLE_PROVISIONING_PROFILE
   ```
4. Re-run the failed workflow: Actions → Release Please (run #28495839899) → Re-run failed jobs

---

## 2. Apple Sign In — Name/Email Not Mapped to Keycloak User Profile

See GitHub issue [#105](https://github.com/bluefunda/cai-ios/issues/105) for full details.

### Summary

Apple only sends `name` and `email` in the identity token on the **first authorization**. The `apple-ios` OIDC IDP in Keycloak has no attribute mappers configured to capture these, so new users get a Keycloak record with no display name and potentially no email.

### iOS-side state

`AuthManager.handleAppleAuthorization` already caches name/email locally on first sign-in:

```swift
UserDefaults.standard.set(given,  forKey: "apple_given_name")
UserDefaults.standard.set(family, forKey: "apple_family_name")
UserDefaults.standard.set(email,  forKey: "apple_email")
```

These cached values are **never forwarded to Keycloak**.

### Recommended fix (short term)

After a successful token exchange, if the app has cached name/email from the current Apple credential, call Keycloak's user API to update the profile:

```
PUT /admin/realms/individual/users/{sub}
Authorization: Bearer <access_token>
{ "firstName": "...", "lastName": "...", "email": "..." }
```

This requires the user's own access token to have the `manage-account` realm role (granted by default in Keycloak).

### Recommended fix (long term)

Add the [apple-identity-provider-keycloak](https://github.com/klausbetz/apple-identity-provider-keycloak) extension JAR to the Keycloak container. This extension handles the `authorizationCode` exchange with Apple on the server side and correctly maps `firstName`/`lastName`/`email` into the Keycloak user record without any iOS-side workarounds.

See `docs/keycloak-prod-migration.md` for deployment steps.

---

## 3. CI Secret Update Checklist

After updating the provisioning profile, verify these secrets are current in GitHub repo settings:

| Secret | What it holds | How to update |
|--------|--------------|---------------|
| `APPLE_PROVISIONING_PROFILE` | Base64 of `.mobileprovision` | Regenerate at developer.apple.com (devops@bluefunda.com), base64-encode, paste |
| `APPLE_CERTIFICATE` | Base64 of `Certificates.p12` | Already in `~/Downloads/Certificates.p12` — check expiry first |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the .p12 | From whoever exported it |
| `APPLE_ASC_KEY_ID` | `3Z5Y3Q79HF` | From `AuthKey_3Z5Y3Q79HF.p8` filename |
| `APPLE_ASC_ISSUER_ID` | UUID from App Store Connect | App Store Connect → Keys → Issuer ID |
| `APPLE_ASC_PRIVATE_KEY` | Base64 of `AuthKey_3Z5Y3Q79HF.p8` | `base64 -i ~/Downloads/AuthKey_3Z5Y3Q79HF.p8 \| pbcopy` |
| `APPLE_PROVISIONING_PROFILE_NAME` | Profile display name string | Shown in Apple Developer portal profile list |
