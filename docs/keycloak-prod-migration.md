# Keycloak Production Migration: Native Apple Sign In

Target: `auth.bluefunda.com` (production `keycloak` container)  
Dev reference: `auth-dev.bluefunda.com` (`keycloak-dev` container, already working)

---

## Background

Native Apple Sign In on iOS sends an Apple-issued identity token (JWT signed by Apple) to Keycloak via the OAuth 2.0 Token Exchange grant. Keycloak validates the token against Apple's public keys and issues KC tokens in return.

Three things are required on the Keycloak side:

1. An OIDC identity provider named `apple-ios` configured for the iOS bundle ID (`com.bluefunda.ai`)
2. Token exchange permissions enabled for that IDP, with a client policy allowing `cai-ios` to exchange
3. The `typ` header check disabled on the IDP (Apple JWTs omit the `typ` header claim)

These were all done on dev. The steps below replicate them on production.

---

## Step 1: Upgrade Keycloak to 26.6.4

Keycloak 26.0 has a bug in the `management/permissions` API that prevents setting up IDP token exchange permissions. KC 26.6.4 fixes this.

### 1a. Check the existing production container startup command

```bash
docker inspect keycloak --format '{{json .HostConfig}}' | python3 -m json.tool | grep -A5 "Binds\|PortBindings\|Env"
```

Note down: volume mounts, env vars, and the KC start command. You will need them for the new container.

### 1b. Pull the new image

```bash
docker pull quay.io/keycloak/keycloak:26.6.4
```

### 1c. Stop and remove the old container

```bash
docker stop keycloak
docker rm keycloak
```

### 1d. Start KC 26.6.4 with the same volumes and updated features

The critical changes vs the old start command:
- Image: `quay.io/keycloak/keycloak:26.6.4`
- `KC_FEATURES`: must include `token-exchange:v1,scripts,admin-fine-grained-authz:v1`
- If using H2 (dev-file database): add `--db=dev-file --db-username=sa --db-password=password` to the start args. KC 26.6.4 no longer auto-detects the H2 credentials from a pre-built image.
- Use `start` (not `start --optimized`) since this is a new KC version with no pre-built config

Example command (adjust volume paths to match what production uses):

```bash
docker run -d \
  --name keycloak \
  --restart unless-stopped \
  -p 7443:8443 \
  -e KC_HOSTNAME=auth.bluefunda.com \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD='<admin-password>' \
  -e KC_HTTPS_CERTIFICATE_KEY_FILE=/etc/x509/https/tls.key \
  -e KC_FEATURES=token-exchange:v1,scripts,admin-fine-grained-authz:v1 \
  -e KC_RUN_IN_CONTAINER=true \
  -e KC_PROXY=edge \
  -e KC_HTTPS_CERTIFICATE_FILE=/etc/x509/https/tls.crt \
  -v /path/to/certs/privkey.pem:/etc/x509/https/tls.key:rw \
  -v /path/to/keycloak_data:/opt/keycloak/data:rw \
  -v /path/to/theme:/opt/keycloak/themes:rw \
  -v /path/to/certs/fullchain.pem:/etc/x509/https/tls.crt:rw \
  quay.io/keycloak/keycloak:26.6.4 start \
  --db=dev-file \
  --db-username=sa \
  --db-password=password
```

> **Note:** If production uses PostgreSQL instead of H2, omit the `--db` / `--db-username` / `--db-password` args and pass the Postgres connection string via env vars (`KC_DB`, `KC_DB_URL`, `KC_DB_USERNAME`, `KC_DB_PASSWORD`) as before.

### 1e. Confirm startup

```bash
docker logs keycloak --tail 20
```

Expected output includes:
```
Deprecated features enabled: admin-fine-grained-authz:v1, token-exchange:v1
Keycloak 26.6.4 on JVM ... started in Xs.
```

Liquibase will automatically migrate the existing realm data — this is safe and reversible.

---

## Step 2: Get an admin token

All subsequent API calls require an admin bearer token. Run this once and reuse `$TOKEN`.

```bash
TOKEN=$(curl -sk -X POST "https://localhost:7443/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=admin-cli&username=admin&password=<admin-password>" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```

---

## Step 3: Create the `apple-ios` OIDC identity provider

Skip this step if `apple-ios` already exists in the `individual` realm.

```bash
# Check if it exists
curl -sk "https://localhost:7443/admin/realms/individual/identity-provider/instances/apple-ios" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print('EXISTS:', d.get('alias','NOT FOUND'))"
```

If it does not exist, create it. You will need the client secret — this is a JWT signed with the Apple private key for the `com.bluefunda.ai` app. On dev it is already set; copy the value from dev or regenerate it.

```bash
curl -sk -X POST "https://localhost:7443/admin/realms/individual/identity-provider/instances" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "alias": "apple-ios",
    "displayName": "Apple (iOS native)",
    "providerId": "oidc",
    "enabled": true,
    "config": {
      "clientId": "com.bluefunda.ai",
      "clientSecret": "<apple-client-secret-jwt>",
      "authorizationUrl": "https://appleid.apple.com/auth/authorize",
      "tokenUrl": "https://appleid.apple.com/auth/token",
      "jwksUrl": "https://appleid.apple.com/auth/keys",
      "issuer": "https://appleid.apple.com",
      "useJwksUrl": "true",
      "validateSignature": "true",
      "defaultScope": "openid email",
      "disableUserInfo": "true",
      "syncMode": "IMPORT",
      "disableTypeClaimCheck": "true",
      "tokenExchangeAccountLinkingEnabled": "true"
    }
  }' -w "\nHTTP:%{http_code}"
```

Expected: `HTTP:201`

> **Important:** `clientId` must be `com.bluefunda.ai` (the iOS Bundle ID), **not** `com.bluefunda.auth` (the Apple Service ID). The Service ID is for the web OAuth flow only.

---

## Step 4: Set `disableTypeClaimCheck` on the IDP

Apple identity tokens do not include a `typ` header claim. KC 26.6.4 rejects such tokens by default. This flag disables that check.

If you already included `"disableTypeClaimCheck": "true"` in the create call above, skip this step.

Otherwise, patch the existing IDP:

```bash
# Fetch current IDP config
IDP=$(curl -sk "https://localhost:7443/admin/realms/individual/identity-provider/instances/apple-ios" \
  -H "Authorization: Bearer $TOKEN")

# Patch and PUT
PATCHED=$(echo "$IDP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['config']['disableTypeClaimCheck'] = 'true'
print(json.dumps(d))
")

curl -sk -X PUT "https://localhost:7443/admin/realms/individual/identity-provider/instances/apple-ios" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PATCHED" -w "\nHTTP:%{http_code}"
```

Expected: `HTTP:204`

---

## Step 5: Enable IDP token exchange management permissions

This creates the authorization resource and scope permission for `apple-ios` inside KC's realm-management authorization server.

```bash
PERM=$(curl -sk -X PUT \
  "https://localhost:7443/admin/realms/individual/identity-provider/instances/apple-ios/management/permissions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}')

echo "$PERM"
```

Expected response:
```json
{
  "enabled": true,
  "resource": "<resource-uuid>",
  "scopePermissions": {
    "token-exchange": "<permission-policy-uuid>"
  }
}
```

Save the `scopePermissions.token-exchange` value — you need it in the next step.

```bash
PERMISSION_ID=$(echo "$PERM" | python3 -c "import sys,json; print(json.load(sys.stdin)['scopePermissions']['token-exchange'])")
echo "Permission policy ID: $PERMISSION_ID"
```

---

## Step 6: Create a client policy allowing `cai-ios` to exchange

The `management/permissions PUT` above creates a scope permission with no associated policies. Without a policy, the permission check still denies everyone. We need to attach a client policy that grants the `cai-ios` client permission to exchange.

### 6a. Find the realm-management client UUID (resource server)

```bash
RM_UUID=$(curl -sk "https://localhost:7443/admin/realms/individual/clients?clientId=realm-management" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
echo "realm-management UUID: $RM_UUID"
```

### 6b. Find the `cai-ios` client UUID

```bash
CAIIOS_UUID=$(curl -sk "https://localhost:7443/admin/realms/individual/clients?clientId=cai-ios" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
echo "cai-ios UUID: $CAIIOS_UUID"
```

### 6c. Create a client policy for `cai-ios`

```bash
CLIENT_POLICY=$(curl -sk -X POST \
  "https://localhost:7443/admin/realms/individual/clients/$RM_UUID/authz/resource-server/policy/client" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"allow-cai-ios-token-exchange\",
    \"description\": \"Allows cai-ios to exchange Apple identity tokens\",
    \"type\": \"client\",
    \"logic\": \"POSITIVE\",
    \"decisionStrategy\": \"UNANIMOUS\",
    \"clients\": [\"$CAIIOS_UUID\"]
  }")

echo "$CLIENT_POLICY"
CLIENT_POLICY_ID=$(echo "$CLIENT_POLICY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "Client policy ID: $CLIENT_POLICY_ID"
```

### 6d. Associate the client policy with the scope permission

```bash
# Fetch the current scope permission
SCOPE_PERM=$(curl -sk \
  "https://localhost:7443/admin/realms/individual/clients/$RM_UUID/authz/resource-server/permission/scope/$PERMISSION_ID" \
  -H "Authorization: Bearer $TOKEN")

echo "$SCOPE_PERM"

# Add the client policy to it
PATCHED_PERM=$(echo "$SCOPE_PERM" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['policies'] = d.get('policies', []) + ['$CLIENT_POLICY_ID']
print(json.dumps(d))
")

curl -sk -X PUT \
  "https://localhost:7443/admin/realms/individual/clients/$RM_UUID/authz/resource-server/permission/scope/$PERMISSION_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PATCHED_PERM" -w "\nHTTP:%{http_code}"
```

Expected: `HTTP:201`

---

## Step 7: Smoke test the token exchange

Use a well-formed fake JWT (invalid signature, but correct structure) to confirm that KC reaches the Apple signature validation step rather than failing on permissions or token type.

```bash
HEADER=$(echo -n '{"alg":"RS256","kid":"testkey"}' | base64 | tr '+/' '-_' | tr -d '=')
PAYLOAD=$(echo -n '{"iss":"https://appleid.apple.com","aud":"com.bluefunda.ai","sub":"test123","exp":9999999999,"iat":1700000000}' | base64 | tr '+/' '-_' | tr -d '=')
SIG=$(echo -n 'fakesig' | base64 | tr '+/' '-_' | tr -d '=')
FAKE_TOKEN="${HEADER}.${PAYLOAD}.${SIG}"

curl -sk -X POST "https://localhost:7443/realms/individual/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange" \
  -d "client_id=cai-ios" \
  -d "subject_token=$FAKE_TOKEN" \
  -d "subject_token_type=urn%3Aietf%3Aparams%3Aoauth%3Atoken-type%3Aid_token" \
  -d "subject_issuer=apple-ios" \
  -d "scope=openid" \
  -w "\nHTTP:%{http_code}"
```

**Expected result:** `{"error":"invalid_token","error_description":"invalid token"}` with `HTTP:400`

This confirms:
- ✅ Permission check passed (no "Client not allowed to exchange")
- ✅ Token type check passed (no "token type not supported")
- ✅ KC reached Apple's signature validation, which correctly rejects the fake token

A real Apple identity token from a device will pass the signature check and complete the flow.

---

## Step 8: Update the iOS app to use production auth URL

In `CAI/Services/Environment.swift`, change `authBaseURL` back to production:

```swift
static let authBaseURL = "https://auth.bluefunda.com"
```

Rebuild and test end-to-end on a real device before submitting to App Store review.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Feature not enabled` on management/permissions PUT | `admin-fine-grained-authz:v1` not in `KC_FEATURES` | Add to KC startup env var and restart |
| `token type not supported` | Apple JWT has no `typ` header claim | Set `disableTypeClaimCheck=true` on the IDP (Step 4) |
| `Client not allowed to exchange` | Client policy not associated with scope permission | Redo Step 6d |
| `Wrong user name or password` on KC start (H2) | KC 26.6.4 doesn't auto-detect H2 creds | Add `--db=dev-file --db-username=sa --db-password=password` to start args |
| `invalid_token` with a real Apple token | `clientId` mismatch — `aud` claim won't match | Verify IDP `clientId` is `com.bluefunda.ai` (bundle ID, not Service ID) |
