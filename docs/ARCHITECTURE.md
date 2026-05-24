# CAI iOS – Architecture

## Overview

Native SwiftUI app that talks to the existing **cai-bff** backend via KrakenD gateway.  
All API calls are authenticated with short-lived JWTs obtained from Keycloak.

---

## Stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI (iOS 17+) |
| State | `@Observable` / `ObservableObject` |
| Async | Swift Concurrency (`async/await`, `AsyncThrowingStream`) |
| Networking | `URLSession` + `URLSession.bytes` for SSE |
| Auth | Keycloak OIDC via `ASWebAuthenticationSession` |
| Persistence | Keychain (tokens), in-memory (conversations) |
| Architecture | MVVM |

---

## Module Structure

```
CAI/
├── CAIApp.swift                  # Entry point, DI wiring
├── Models/
│   └── APIModels.swift           # Codable DTOs for every BFF endpoint
├── Utilities/
│   ├── APIClient.swift           # Generic URLSession wrapper, auth injection
│   └── Extensions.swift          # Swift / Foundation helpers
├── Services/
│   ├── ChatServiceProtocol.swift # Streaming chat abstraction
│   ├── BFFChatService.swift      # SSE streaming (POST /chats/{id})
│   ├── NATSChatService.swift     # Legacy NATS alternative (not default)
│   ├── BFFAPIService.swift       # All REST calls (models, chats, MCP…)
│   └── AuthManager.swift         # Keycloak OAuth lifecycle + Keychain
├── ViewModels/
│   └── ChatManager.swift         # Conversations, models, MCP selection
└── Views/
    ├── ContentView.swift          # Auth gate + tab shell
    ├── ChatView.swift             # Chat thread + streaming input
    ├── ConversationsView.swift    # Chat history browser
    ├── SettingsView.swift         # Account, model, MCP, rate-limit links
    ├── RateLimitView.swift        # Token usage / rate-limit status
    └── StorageView.swift          # Cloud storage browser (basic)
```

---

## Authentication Flow

```
App launch
  └─ AuthManager.restoreSession()
       ├─ Load refreshToken from Keychain
       ├─ POST /realms/{realm}/protocol/openid-connect/token (grant=refresh_token)
       └─ On success → isAuthenticated = true

User taps "Sign in with Keycloak"
  └─ ASWebAuthenticationSession opens Keycloak login page
       └─ Keycloak redirects to cai://auth/callback?code=...
            └─ POST /token (grant=authorization_code)
                 ├─ Store access_token + refresh_token in Keychain
                 ├─ Decode JWT → User struct
                 └─ isAuthenticated = true

Every API call
  └─ APIClient refreshes token if expires in < 60 s
       └─ Injects Authorization: Bearer {token}

Logout
  └─ POST /logout (revoke refresh token)
       └─ Clear Keychain → isAuthenticated = false
```

---

## Chat Streaming Flow

```
sendMessage(text)
  └─ ChatManager builds ChatRequest{chatId, model, prompt, mcpServer}
       └─ BFFChatService.sendMessage(request)
            └─ POST /chats/{chatId}
               Body: {"type":"Human","model":"groq","prompt":"...","mcp_server_name":"..."}
               Accept: text/event-stream

            SSE events received:
              stream_start  → ignore (UI already shows placeholder)
              stream_chunk  → append to assistant message content
              stream_end    → finalize content, trigger title generation
              stream_heartbeat → no-op
              stream_error  → surface in UI error state

Title generation (async, after first user message):
  └─ POST /chats/{chatId}/title  Body: {"message": "first user prompt"}
       └─ Update conversation.title in ChatManager
```

---

## Data Loading on Connect

When user authenticates, `ChatManager.connect()` fires:
1. `GET /chats` → populate `conversations` list
2. `GET /models` → populate `availableModels`
3. `GET /mcp` → populate all available MCP servers
4. `GET /mcp/user` → mark subscribed servers

The in-memory conversation list is a subset of server-side data.  
Full message history for a conversation is loaded on-demand via `GET /chats/{id}/messages`.

---

## Token Refresh Strategy

`APIClient.request()` calls `AuthManager.refreshTokenIfNeeded()` before every request.  
On 401 response the client throws `APIError.unauthorized` which propagates to ChatManager,
which calls `AuthManager.logout()` and routes user back to LoginView.

---

## Error Handling

| Error type | Handling |
|------------|----------|
| 401 Unauthorized | Token refresh → retry once, then force re-login |
| 4xx Client errors | Surface human-readable message via `chatManager.error` |
| 5xx Server errors | Same as 4xx + optional retry for idempotent GETs |
| Network offline | Graceful UI message, no crash |
| Stream cancelled | Clean finish via `CancellationError`, no error shown |
| Token expired | Auto-refresh before request if within 60 s threshold |

---

## Key Constraints

- **No WKWebView** — every screen is native SwiftUI
- **No third-party dependencies** — URLSession, AuthenticationServices, Security frameworks only
- **No local database** — conversations are in-memory; tokens in Keychain only
- **No hardcoded credentials** — all config via `AppConfig` struct referencing compile-time constants
- **iOS 17+ minimum** — uses `@Observable`, `.defaultScrollAnchor`, `ScrollViewReader`
