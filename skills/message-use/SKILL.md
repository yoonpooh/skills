---
name: message-use
description: Quickly read, search, summarize, and triage local macOS Messages/iMessage data from the read-only chat.db cache without opening Messages.app, and use the app UI only for explicitly requested UI or state-changing work. Use when the user asks about local texts, iMessage, SMS, unread messages, verification codes, message summaries, spam texts, or Messages.app cleanup; do not use for sending replies.
---

# Message Use

## Overview

Use this skill to inspect and manage local macOS Messages without sending messages. For every read-only request, query `~/Library/Messages/chat.db` without launching, activating, or scripting Messages.app. Treat the database as a fast local-cache snapshot that may differ from the app's synced visible state. Use the app UI only when the user explicitly requests UI/current-visible state, requests a state change, or approves UI access after a database limitation is reported.

## Safety

- Treat Messages data as private. Read only the conversations, senders, dates, and text needed for the request.
- Do not send messages with this skill.
- Ask before deleting conversations or messages. Deletion can sync through iCloud and be hard to reverse.
- For marking messages read, require an explicit user request or clear approval for the target set.
- Before any state-changing action, show the target count and the minimum context needed to identify it. Mask sender identifiers by default; include message snippets only when the user's request requires reading or disambiguation.
- Never edit `chat.db` directly. Use SQLite only for read-only inspection and verification.
- Never type into the conversation message field (`messageBodyField`). Sending is outside this skill.
- Never launch, activate, or foreground Messages.app for a read-only request unless the user explicitly asks to use the app.

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

Do not assume `message.text` contains the visible body. On current macOS versions, some rows omit cache-readable text while Messages.app can still display it. Say when a database result omits visible text and return the available sender/date/service metadata. Ask before opening Messages.app; never switch to the UI automatically.

## Automation Routing

Treat every non-mutating lookup as a database-only task, regardless of whether it concerns unread, read, recent, searched, or specific messages.

Use this routing:

1. Use the read-only database for all ordinary reads: unread lists, recent messages, verification codes, sender/phrase searches, summaries, and historical lookup.
2. Do not call AppleScript or Computer Use during a read-only database request.
3. If cached text is unavailable, return partial metadata and ask whether the user wants the app opened for the missing content.
4. Use native Messages AppleScript only when the user explicitly asks for supported live app/chat metadata.
5. Use Computer Use for explicitly requested current visible UI state, filters, transcripts missing from the DB, selection changes, marking read, and deletion.

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

Report this as the local database unread-row count, not the current Messages.app badge count. Synced and historical rows can retain `is_read=0` long after they disappear from the visible unread surface. For user requests such as "읽지 않은 내용 보여줘", default to a recent bounded query (30 days unless the user specifies otherwise), label it as cache-based, and group by conversation when useful:

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

For unread counts and summaries:

1. Run a recent bounded `chat.db` query first and do not open Messages.app.
2. Return the readable message text with sender/chat label and received time. Group repeated rows by conversation when that makes the result easier to scan.
3. Label counts precisely as cache unread rows or distinct cache conversations.
4. If text is unavailable, return the row's sender/chat label, time, and `[DB에서 본문 확인 불가]`.
5. Mention once that local cached state may be stale or incomplete; do not turn that caveat into automatic UI verification.
6. Only if the user explicitly asks for the app's current visible unread state, use Messages.app's unread filter through Computer Use.

For ordinary searches, query `chat.db` with a narrow sender, phrase, chat, and date scope. Because one message can be joined to more than one chat row, use `distinct` or deduplicate by `m.ROWID` before reporting counts or results. Only use the Messages.app search field when the user explicitly asks for the app's current visible results or when the database cannot expose the requested content and the user approves opening the app. Clear the app search field after inspection. App search results can include conversations, message snippets, links, and attachments; label the result type instead of treating every row as a conversation.

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

- For ordinary read-only counts, report `chat.db` results as cache-based without opening Messages.app.
- For explicitly requested current visible counts, verify in Messages.app and distinguish them from cache counts.
- For read status, compare the app's unread filter and row actions before and after.
- For deletion, verify the target no longer appears in the active conversation/search surface; note if rows remain in local database tables as cache or recovery records.
- When DB and UI disagree, trust the user-visible Messages.app state for cleanup, and report the DB/UI mismatch.
