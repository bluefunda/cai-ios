# Feature Mapping: Web → iOS

## MVP (Implemented)

| Web Feature | iOS Equivalent | Status |
|-------------|----------------|--------|
| Keycloak OAuth login | ASWebAuthenticationSession OAuth flow | ✅ |
| Realm selection (trm / individual) | Segmented picker on LoginView | ✅ |
| Token refresh (silent) | `AuthManager.refreshTokenIfNeeded()` | ✅ |
| Keychain token persistence | Security framework Keychain | ✅ |
| Chat send + streaming | SSE via `URLSession.bytes` | ✅ |
| Stop streaming | `POST /chats/{id}/stop` + task cancel | ✅ |
| Conversation list (in-memory) | `ChatManager.conversations` | ✅ |
| New conversation | `ChatManager.newConversation()` | ✅ |
| Delete conversation | Swipe-to-delete in ConversationsView | ✅ |
| Search conversations | `.searchable` modifier | ✅ |
| Model selection (Groq/OpenAI/DeepSeek) | ModelPicker toolbar menu | ✅ |
| MCP server selection | MCPServerSelectionView | ✅ |
| User info display (avatar, name, email) | UserInfoRow in SettingsView | ✅ |
| Sign out | Confirmation dialog → `AuthManager.logout()` | ✅ |
| Connection status banner | `ConnectionBanner` component | ✅ |

## Phase 2 (API-integrated)

| Web Feature | iOS Target | Status |
|-------------|------------|--------|
| Load models from `/models` | `BFFAPIService.fetchModels()` → ChatManager | ✅ |
| Load chats from `/chats` | `BFFAPIService.fetchChats()` → ChatManager | ✅ |
| Load MCP servers from `/mcp` | `BFFAPIService.fetchMCPServers()` | ✅ |
| User subscribed MCP from `/mcp/user` | `BFFAPIService.fetchUserMCPServers()` | ✅ |
| Rate limit status | `RateLimitView` + `BFFAPIService.fetchRateLimit()` | ✅ |
| Load messages from API | `BFFAPIService.fetchChatMessages()` | ✅ |

## Phase 3 (Future)

| Web Feature | iOS Target | Notes |
|-------------|------------|-------|
| Cloud storage browser | `StorageView` (basic file list) | Partial |
| File upload for prompt | Photo library + `/storage/upload` | Planned |
| Token usage dashboard | Summary card in SettingsView | Planned |
| Stripe subscription info | Card in SettingsView | Planned |
| Markdown rendering | AttributedString / third-party? | Planned |
| Chart rendering in AI responses | Charts framework | Planned |
| Push notifications | APNs integration | Planned |
| Offline message queue | SwiftData persistence | Planned |
| Analytics tab | Web-only (complex dashboards) | Web-only |
| SAP/ABAP change requests | Web-only (complex workflows) | Web-only |
| Admin tools | Web-only | Web-only |

## Web-Only Features

These features are too complex for iOS MVP or require SAP-specific integrations:

- Analytics dashboard (Recharts-based visualizations)
- ABAP change request management
- Keycloak admin user management
- SAP APIM CSRF token flows
- Detailed Stripe plan management UI
- NATS pub/sub direct integration
- Google Analytics connector

## Native-Only Improvements

- Keychain for secure credential storage (more secure than browser cookies)
- Face ID / Touch ID re-authentication (planned)
- Background task cancellation with proper `Task` lifecycle
- iOS share sheet for exporting chat messages
- Haptic feedback on send/receive
- Dynamic Type for accessibility
