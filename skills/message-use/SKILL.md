---
name: message-use
description: Work with the user's local macOS Messages/iMessage data and Messages.app for reading, searching, summarizing, unread-message triage, marking conversations read, and deleting or cleaning spam conversations. Use when the user asks about local texts, iMessage, SMS, unread messages, verification codes, message summaries, spam texts, or Messages.app cleanup; do not use for sending replies.
---

# Message Use

## Overview

Use this skill to inspect and manage local macOS Messages without sending messages. Use native Messages AppleScript only for supported non-UI app metadata, and use Computer Use from the start for every task that reads or manipulates the Messages.app UI. Treat the current Messages.app UI as the source of truth for visible unread state and cleanup. Use `~/Library/Messages/chat.db` as a read-only supplement for narrow historical searches and verification.

## Safety

- Treat Messages data as private. Read only the conversations, senders, dates, and text needed for the request.
- Do not send messages with this skill.
- Ask before deleting conversations or messages. Deletion can sync through iCloud and be hard to reverse.
- For marking messages read, require an explicit user request or clear approval for the target set.
- Before any state-changing action, show the target count and the minimum context needed to identify it. Mask sender identifiers by default; include message snippets only when the user's request requires reading or disambiguation.
- Never edit `chat.db` directly. Use SQLite only for read-only inspection and verification.
- Never type into the conversation message field (`messageBodyField`). Sending is outside this skill.

## Local Data

Messages stores local data at:

```bash
~/Library/Messages/chat.db
```

Use read-only SQLite access:

```bash
sqlite3 -readonly "$HOME/Library/Messages/chat.db" "select count(*) from message;"
```

Important tables:

- `message`: text, dates, read flags, spam flag, sender handle id.
- `handle`: phone/email identifiers.
- `chat`: conversation metadata.
- `chat_message_join`: message-to-chat relationship.
- `chat_handle_join`: chat participants.

Messages dates are Apple epoch nanoseconds. Convert with:

```sql
datetime(message.date / 1000000000 + 978307200, 'unixepoch', 'localtime')
```

Do not assume `message.text` contains the visible body. On current macOS versions, many SMS rows have `text`, `attributedBody`, and payload columns all empty while Messages.app still exposes the body through accessibility. Say when a database result omits visible text, and switch to the app UI for the requested current conversations.

## Automation Routing

Use this routing:

1. Use native Messages AppleScript for supported non-UI app and chat metadata.
2. Use the read-only database for narrow historical lookup or metadata the native API does not expose.
3. Use Computer Use from the start for visible unread state, search, filters, conversation rows, transcripts, menus, dialogs, selection changes, marking read, and deletion.

Tested native AppleScript capabilities on this Mac:

- Supported: app availability, chat count, and chat metadata such as id, name, and participants.
- Not supported by the native API: reading a chat's message collection, chat read status, current selection, marking read, or deleting a chat/message.

Do not repeatedly probe known-unsupported AppleScript properties or invent write commands. Do not use `System Events`, JXA accessibility scripting, `sms:` deep-link UI control, coordinate clicks, or keyboard-event synthesis as a substitute for Computer Use. Querying native Messages AppleScript objects is allowed because it is an app API, not UI automation.

Safe AppleScript availability and metadata probes:

```bash
osascript -e 'tell application "Messages" to count chats'
```

```applescript
tell application "Messages"
  set c to item 1 of chats
  return {id of c, name of c, count of participants of c}
end tell
```

Run Messages AppleScript commands one at a time. Do not run AppleScript and Computer Use operations in parallel; app state and accessibility indexes can change between actions.

Computer Use element indexes are ephemeral. Fetch fresh app state immediately before every click or secondary action; never reuse an index from an older state.

## Read-Only Tasks

Raw database unread flag count:

```bash
sqlite3 -readonly "$HOME/Library/Messages/chat.db" \
  "select count(*) from message where is_from_me=0 and is_read=0;"
```

Do not report this raw count as the current Messages.app unread count. Synced and historical rows can retain `is_read=0` long after they disappear from the visible unread surface. Group by year or bound the query to a recent period when diagnosing the mismatch:

```bash
sqlite3 -readonly "$HOME/Library/Messages/chat.db" \
  "select strftime('%Y', datetime(date / 1000000000 + 978307200, 'unixepoch')) as year,
          count(*)
   from message
   where is_from_me=0 and is_read=0
   group by year
   order by year;"
```

Recent unread summary candidates:

```bash
sqlite3 -readonly "$HOME/Library/Messages/chat.db" \
  "select m.ROWID,
          coalesce(c.display_name, c.chat_identifier, h.id, 'unknown') as chat_label,
          h.id as handle,
          datetime(m.date / 1000000000 + 978307200, 'unixepoch', 'localtime') as received_at,
          replace(coalesce(m.text, '[body unavailable in database]'), char(10), ' ') as text
   from message m
   left join handle h on h.ROWID = m.handle_id
   left join chat_message_join cmj on cmj.message_id = m.ROWID
   left join chat c on c.ROWID = cmj.chat_id
   where m.is_from_me=0
     and m.is_read=0
     and m.date >= (strftime('%s', 'now', '-30 days') - 978307200) * 1000000000
   order by m.date desc
   limit 20;"
```

Search by exact phrase or sender with narrow limits. Avoid broad full-history dumps.

For current unread counts and summaries:

1. Use AppleScript first for supported chat metadata, without expecting message bodies or unread state.
2. Open Messages.app with Computer Use and use its Filter menu's unread view when available.
3. Read only the visible unread conversation rows and requested transcripts through accessibility.
4. Count unread conversations separately from unread messages; the sidebar represents conversations, not individual message rows.
5. Use the database only to add dates, service metadata, or narrow historical context.

For search, use the Messages.app search field and clear it after inspection. Search results can include conversations, message snippets, links, and attachments; label the result type instead of treating every row as a conversation.

## Spam Cleanup

Spam candidates may come from:

- User-named senders or phrases.
- Short-code or unknown-number marketing patterns.
- Repeated messages with links, unsubscribe language, prize/loan/crypto/ad wording, or Korean ad markers such as `(광고)`.
- `message.is_spam=1`, when populated. This local DB may have zero spam-flagged rows, so do not rely on it alone.

Cleanup flow:

1. Build a conservative candidate list from Messages.app search/filter results, optionally supplemented by read-only queries.
2. Exclude known contacts, finance, medical, legal, login/security, delivery, and work-related messages unless the user explicitly names them.
3. Present the number of candidate conversations, masked sender/chat labels, category, and date range. Include a minimal snippet only when needed to distinguish candidates.
4. Ask for explicit deletion approval.
5. Delete through Messages.app with Computer Use, not by editing `chat.db`.
6. Verify that target chats/messages are no longer visible or no longer present in the expected active query.

## Marking Read

Do not set `message.is_read` in the database. Native Messages AppleScript does not expose a read-status mutation, so marking read is always a Computer Use task:

1. Build the exact target conversation list from the Messages.app unread filter. Do not derive it from the raw database flag count alone.
2. Ask for approval unless the user already requested that exact target, such as "mark all unread texts read".
3. Use Computer Use on Conversation > Mark All as Read (`대화 > 모두 읽음으로 표시`) for all unread conversations, or the row's Mark as Read action for selected conversations.
4. Refresh app state before each action and never reuse stale element indexes.
5. Verify that all unread dots/badges disappeared in Messages.app. Use a recent bounded database query only as supporting evidence.

If UI state is unclear, stop and report the uncertainty instead of directly mutating the database.

## Deletion

Prefer deleting whole spam conversations only when the user requested cleanup by sender/category. Individual message deletion may require precise UI selection and should be avoided unless the user identifies the exact message.

Native Messages AppleScript does not expose chat/message deletion, so deletion is always a Computer Use task. Search or select the exact approved target in Messages.app, refresh app state, and use the conversation row or message bubble's exposed delete action. Conversation deletion and individual-message deletion are different operations, so verify the requested level before acting.

In the confirmation dialog, choose Delete (`삭제`). Do not choose Delete and Report Junk (`삭제 및 스팸 신고`) unless the user explicitly requested reporting. Ask for confirmation if the user has not already approved the exact target set.

After deletion, verify the item disappeared from the active conversation/search surface. Messages.app may move it to Recently Deleted; report that state and do not permanently erase Recently Deleted items without a separate explicit request.

Do not promise permanent deletion. Messages may remain in synced devices, recoverable areas, or local cache until Messages/iCloud finishes syncing.

## Verification

- For current visible counts, verify in Messages.app; use `sqlite3 -readonly` only as supporting evidence.
- For read status, compare the app's unread filter and row actions before and after.
- For deletion, verify the target no longer appears in the active conversation/search surface; note if rows remain in local database tables as cache or recovery records.
- When DB and UI disagree, trust the user-visible Messages.app state for cleanup, and report the DB/UI mismatch.
