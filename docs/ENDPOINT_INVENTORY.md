# BFF API Endpoint Inventory

Base URL: `https://api.bluefunda.com/ai`  
Auth: `Authorization: Bearer {access_token}` on every request except `/health`.

---

## Health

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | No | Gateway health check |

---

## User

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/userinfo` | Yes | Keycloak userinfo (sub, email, name, roles) |
| GET | `/settings` | Yes | User preferences |

---

## Models

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/models` | Yes | Available LLM models list |

Response: array of `{ id, name, provider?, description? }` or wrapped object.

---

## Chats

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/chats` | — | All conversations for current user |
| GET | `/chats/{chatId}/messages` | — | Full message history |
| GET | `/chats/{chatId}/context` | — | Context (role+content only) for AI |
| POST | `/chats/{chatId}` | `{"type":"Human","model":"groq","prompt":"...","mcp_server_name":"...","mcp_server_url":"..."}` | Stream response (SSE) |
| POST | `/chats/{chatId}/persist` | `{"role":"user","content":"..."}` | Persist a message server-side |
| POST | `/chats/{chatId}/title` | `{"message":"..."}` | Auto-generate conversation title |
| POST | `/chats/{chatId}/stop` | `{}` | Abort in-progress stream |

### SSE Event Types (POST /chats/{chatId})

```jsonc
// stream_start
{ "type": "stream_start", "chat_id": "...", "session_id": "..." }

// stream_chunk
{ "type": "stream_chunk", "content": "Hello", "chunk_id": 1, "total_content_length": 5 }

// stream_end
{ "type": "stream_end", "total_chunks": 42, "full_content": "Hello world", "stopped": false }

// stream_heartbeat
{ "type": "stream_heartbeat", "session_id": "...", "chunks": 10, "content_length": 100 }

// stream_error
{ "type": "stream_error", "message": "...", "details": "..." }
```

---

## MCP Servers

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/mcp` | — | All available MCP servers |
| GET | `/mcp/user` | — | Servers subscribed by current user |
| POST | `/mcp/select` | `{"server_id":"..."}` | Subscribe to a server |
| PUT | `/mcp/config` | `{"config":{}}` | Update server config |

---

## Rate Limits

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/rate-limit` | — | Current usage + limits |
| PUT | `/rate-limit` | `{"limit":100}` | Update limit (admin) |
| POST | `/rate-limit/block` | `{"blocked":false}` | Block/unblock user (admin) |

### Rate Limit Response Shape

```json
{
  "plan_name": "free",
  "daily_tokens_used": 1234,
  "daily_tokens_limit": 10000,
  "monthly_tokens_used": 5000,
  "monthly_tokens_limit": 100000,
  "hourly_tokens_used": 50,
  "hourly_tokens_limit": 500,
  "is_blocked": false,
  "block_reason": ""
}
```

---

## Stripe / Subscription

| Method | Path | Description |
|--------|------|-------------|
| GET | `/stripe/subscription` | Current subscription info |
| GET | `/stripe/plans` | Available plans |

---

## Storage (MinIO)

| Method | Path | Query | Description |
|--------|------|-------|-------------|
| GET | `/storage/list` | `bucket`, `prefix` | List objects |
| POST | `/storage/upload` | `bucket` | Upload file (multipart) |
| GET | `/storage/download` | `bucket`, `key` | Download file |
| DELETE | `/storage/delete` | `bucket`, `key` | Delete object |
| POST | `/storage/folder` | — | Create folder (`{"bucket":"...","folder":"..."}`) |
| GET | `/storage/presigned-url` | `bucket`, `key`, `action` | Get presigned S3 URL |
| GET | `/storage/stats` | `bucket` | Bucket usage stats |

---

## Greetings

| Method | Path | Description |
|--------|------|-------------|
| GET | `/greetings` | Welcome messages for home screen |

---

## Notes

- All endpoints require `Authorization: Bearer {token}` except `/health`.
- Gateway extracts JWT claims and forwards `X-User-ID`, `x-role`, `X-Realm` headers to the BFF automatically — the iOS client only needs to send the `Authorization` header.
- Streaming endpoint (`POST /chats/{chatId}`) has 24-hour server timeout; iOS client uses 120 s.
- Error responses delegate to the BFF backend; shape varies but typically `{"error":"...","message":"..."}`.
- Pagination: not implemented at gateway level; backends may add it in the future.
