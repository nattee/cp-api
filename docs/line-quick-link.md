# LINE Quick Link — Admin-Initiated Onboarding

## Problem

When a VIP adds the LINE OA and sends a message, the current flow requires:
1. Admin generates a linking code in the web UI
2. Admin communicates the code to the VIP (out of band)
3. VIP types `link <code>` in LINE chat

This is friction for the VIP. Ideally the VIP just chats, and an admin links them with zero effort from the VIP's side.

## Goals

- VIP sends a message → admin sees it → admin clicks "Create & Link" → done
- VIP never has to type a command or receive a code
- Prevent resource exhaustion from spam or bot accounts
- No ChatMessage or LLM processing for unlinked users

## Design

### New model: `LineContact`

A lightweight record for LINE users who have messaged the bot but are not linked to a User account. One row per unique LINE user ID.

```ruby
# Schema
create_table :line_contacts do |t|
  t.string  :line_user_id, null: false, index: { unique: true }
  t.string  :display_name          # from LINE profile API, if available
  t.json    :recent_messages       # last K messages as JSON array
  t.integer :message_count, default: 0, null: false
  t.datetime :first_seen_at, null: false
  t.datetime :last_seen_at, null: false
  t.timestamps
end
```

### `recent_messages` JSON structure

Array of the last K (K=10) messages, oldest first:

```json
[
  { "text": "Hello, is this the CP department?", "at": "2026-04-04T10:30:00+07:00" },
  { "text": "I'd like to enroll", "at": "2026-04-04T10:30:15+07:00" }
]
```

Bounded by design — never grows beyond K entries. Each entry is ~200 bytes worst case, so 10 entries ≈ 2KB per contact. Even 1,000 spam contacts = 2MB — negligible.

**Why JSON instead of a detail table**: One table, no JOINs, no FK cleanup, self-contained. The race condition from concurrent webhook jobs is possible (two messages clobber each other's JSON update) but the consequence is trivial — losing one preview message from an unlinked user. Use MySQL `JSON_ARRAY_APPEND` to minimize the window.

### Rate limiting

Unlinked users are rate-limited to prevent resource exhaustion:

- **Message recording**: Max N messages per hour per `line_user_id` (e.g. N=20). Beyond that, silently drop (no reply, no record update).
- **Reply**: Only reply once per contact (on first message or after long gap), not on every message. Prevents the bot from being used as a reply oracle.
- **No LLM processing**: Unlinked users never trigger ChatJob or LlmService.
- **No ChatMessage storage**: Messages only go into the bounded `recent_messages` JSON.

### Cleanup

- Auto-expire `LineContact` records older than 30 days (same pattern as `ApiEvent.cleanup`).
- Once a contact is linked to a User, the `LineContact` row is deleted.

### Flow

#### Unlinked user messages the bot

```
LINE message → WebhookController → EventDispatchJob → EventRouter → MessageRouter
  → User not found for this line_user_id
  → Rate-limit check (skip if over limit)
  → Upsert LineContact (update message_count, last_seen_at, append to recent_messages)
  → Reply (only on first contact): "Thanks for your message! An admin will set up your account shortly."
```

#### Admin reviews and links

1. Admin visits `/line_contacts` — sees list of unlinked LINE users with message count, last seen, preview of latest message.
2. Admin clicks a contact → sees all recent_messages (up to K) for context.
3. Admin clicks "Create & Link" → form pre-fills with display_name if available. Admin enters username, email, name, role.
4. On submit:
   - Creates User with `provider: "line"`, `uid: line_user_id`, `llm_consent: true`
   - Deletes the `LineContact` row
   - Optionally sends a LINE push message: "Your account is now set up! You can start chatting."

### Security considerations

| Threat | Mitigation |
|---|---|
| Spam account creation in `line_contacts` | One row per LINE user ID (upsert), auto-expire after 30 days |
| Database bloat from messages | Bounded JSON array (K=10), ~2KB per contact |
| LLM resource exhaustion | No LLM processing for unlinked users |
| Reply oracle (attacker probes bot behavior) | Reply only on first contact, not every message |
| Identity spoofing | Admin verifies identity before creating User — human in the loop |
| Privilege escalation | Auto-created users get `viewer` role, admin can adjust |

### Admin UI

**Index page** (`/line_contacts`):
- Table: LINE User ID, Display Name, Messages, First Seen, Last Seen, Actions
- "Create & Link" button per row

**Show page** (`/line_contacts/:id`):
- Recent messages displayed as a simple chat-style list
- "Create & Link" button → opens a user creation form with LINE fields pre-filled

### Changes to existing code

| File | Change |
|---|---|
| `app/models/line_contact.rb` | New model |
| `db/migrate/*_create_line_contacts.rb` | New migration |
| `app/controllers/line_contacts_controller.rb` | New controller (admin-only) — index, show, create_and_link |
| `app/services/line/message_router.rb` | Record contact for unlinked users instead of just replying |
| `app/views/line_contacts/` | Index + show + link form views |
| Sidebar | Add "LINE Contacts" link under ADMIN section |

### Future considerations

- **LINE Profile API**: Fetch display name and profile picture from LINE when a new contact appears. Helps admin identify the VIP.
- **Notification**: Badge count on sidebar "LINE Contacts" link showing unlinked contacts waiting for admin action.
- **Bulk link**: If multiple VIPs message at once (e.g. orientation day), admin can process them quickly from the list.
