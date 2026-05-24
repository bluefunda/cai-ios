# CAI iOS

Native SwiftUI app for the BlueFunda Cognitive AI Interface.  
Connects to the existing `cai-bff` backend via KrakenD gateway at `api.bluefunda.com`.

---

## Requirements

| Tool | Version |
|------|---------|
| Xcode | 15.0+ |
| iOS target | 17.0+ |
| Swift | 5.9+ |
| macOS (host) | 14.0+ (Sonoma) |

No third-party dependencies — only Apple SDKs.

---

## Setup

1. **Clone**
   ```
   git clone <repo-url>
   cd cai-ios
   ```

2. **Open in Xcode**
   ```
   open CAI.xcodeproj
   ```

3. **Configure signing**  
   In Xcode → Project → Signing & Capabilities:
   - Set your **Development Team**
   - Bundle ID is `com.bluefunda.cai` (change if needed)

4. **Register the URL scheme**  
   The app uses the `cai://` custom URL scheme for Keycloak OAuth callbacks.  
   Verify it exists in Info.plist → URL Types → `cai`.  
   (Should already be present — check `CAI/Info.plist`.)

5. **Run**  
   Select an iPhone 15 simulator (iOS 17+) and press ▶.

---

## Authentication

The app authenticates with **Keycloak** (OIDC/OAuth2).

- Default Keycloak URL: `https://auth.bluefunda.com`
- Client ID: `cai-ios`
- Redirect URI: `cai://auth/callback`
- Realms: `individual`, `trm`

On first launch, tap **Sign in with Keycloak** → select a realm → complete login in Safari.  
Tokens are stored in the iOS Keychain and auto-refreshed silently.

---

## Architecture

```
CAI/
├── CAIApp.swift              # Entry point, DI wiring, StateObject lifecycle
├── Models/
│   └── APIModels.swift       # Codable DTOs for all BFF endpoints
├── Utilities/
│   ├── APIClient.swift       # Generic URLSession wrapper with auth injection
│   └── Extensions.swift      # Date, String, Color, View helpers
├── Services/
│   ├── ChatServiceProtocol.swift  # Streaming chat abstraction
│   ├── BFFChatService.swift       # SSE streaming via POST /chats/{id}
│   ├── BFFAPIService.swift        # REST calls (models, chats, MCP, etc.)
│   ├── NATSChatService.swift      # Legacy NATS alternative
│   └── AuthManager.swift          # Keycloak OAuth + Keychain
├── ViewModels/
│   └── ChatManager.swift     # Conversations, models, MCP, rate-limit state
└── Views/
    ├── ContentView.swift         # Auth gate + tab shell
    ├── ChatView.swift            # Chat thread + SSE streaming
    ├── ConversationsView.swift   # Chat history with search & delete
    ├── SettingsView.swift        # Account, model, MCP settings
    ├── RateLimitView.swift       # Token usage / rate-limit display
    └── StorageView.swift         # Cloud storage placeholder
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for a full walkthrough.

---

## API Endpoints

All endpoints are documented in [`docs/ENDPOINT_INVENTORY.md`](docs/ENDPOINT_INVENTORY.md).

Base URL: `https://api.bluefunda.com/ai`

| Feature | Endpoint |
|---------|----------|
| Chat streaming | `POST /chats/{id}` (SSE) |
| List chats | `GET /chats` |
| Available models | `GET /models` |
| MCP servers | `GET /mcp`, `GET /mcp/user` |
| Rate limits | `GET /rate-limit` |
| User info | `GET /userinfo` |
| Storage | `GET /storage/list`, `POST /storage/upload`, etc. |

---

## Features

### MVP (Implemented)
- ✅ Keycloak OAuth login (realm selector)
- ✅ Silent token refresh + Keychain persistence
- ✅ Chat send with SSE streaming
- ✅ Stop generation
- ✅ Conversation list (loaded from `/chats`)
- ✅ Lazy message load (loaded on conversation select)
- ✅ Auto title generation via `/chats/{id}/title`
- ✅ LLM model selection (loaded from `/models`)
- ✅ MCP server selection (loaded from `/mcp`)
- ✅ Rate limit view (`/rate-limit`)
- ✅ User account display
- ✅ Sign out

### Coming in Phase 3
- Cloud storage browser (basic file list)
- File upload for chat prompts
- Push notifications
- Offline message queue
- Markdown rendering in AI responses

See [`docs/FEATURE_MAPPING.md`](docs/FEATURE_MAPPING.md) for the full web→iOS mapping.

---

## Tests

Unit tests are in `CAITests/`. Run via:
- Xcode: `⌘U`
- CLI: `xcodebuild test -scheme CAI -destination 'platform=iOS Simulator,name=iPhone 15'`

Test coverage includes:
- `APIModels` — JSON decoding for all response types
- `ChatManager` — conversation lifecycle, message sending, streaming
- `Extensions` — string truncation, date parsing, size formatting

---

## Backend Compatibility

| Component | Version |
|-----------|---------|
| cai-gw | KrakenD v2.8+ |
| cai-bff | whatever ships behind the gateway |
| Keycloak | 22+ |

The iOS app calls only the modern BFF endpoints (no `/rest/trm/v1` legacy paths).  
Do not update the backend API contracts without a corresponding iOS update.

---

## Troubleshooting

**"Sign in" button does nothing:**  
Check that the `cai://` URL scheme is registered in `Info.plist`.

**401 errors after login:**  
Token may have expired. Sign out and back in. If recurring, check Keycloak session limits.

**Models or MCP list is empty:**  
Verify the BFF backend is reachable at `https://api.bluefunda.com/ai/models`.

**Chat stops mid-stream:**  
Check network connectivity. The SSE connection has a 120 s timeout on the iOS side.

---

## License

Internal — BlueFunda proprietary.
