---
name: mail-use
description: Use the local Mac Mail.app cache and database to quickly find, read, and summarize email without opening Mail.app, and use Mail.app automation only for explicitly requested UI or state-changing work. Use when the user asks about Apple Mail, Mail.app, unread or local email messages, inbox/archive/search results, senders, subjects, email cleanup, email summaries, email drafts, or actions on currently selected Mail.app messages.
---

# Mail Use

## Overview

Use this skill for email work on the user's Mac. For every read-only request, query the on-disk Mail cache and `Envelope Index` without launching, activating, or scripting Mail.app. Use Mail.app automation only when the user explicitly requests an app-visible or state-changing action, or approves it after the cache proves insufficient.

## Safety

- Treat mail as private data. Read only the accounts, senders, dates, and messages needed for the request.
- Ask before sending, deleting, archiving, moving, or marking messages read/unread.
- Before a state-changing action, show the exact target: count, account/mailbox when known, sender, date, and subject.
- Treat "delete" as moving to the account Trash/Deleted mailbox. Ask again before permanent deletion or emptying Trash.
- Prefer creating a visible draft over sending directly unless the user explicitly asks to send.
- Summarize by default. Quote only short excerpts when needed.
- If results are ambiguous, list the likely matches and ask which one to use.
- Say when a result is based on local Mail.app cache, because messages not downloaded to this Mac may be missing.
- Never launch, activate, or foreground Mail.app for a read-only request unless the user explicitly asks to use the app.

## Workflow

Treat every non-mutating lookup as a cache-only task, regardless of whether it concerns unread, read, recent, archived, sent, searched, or specific messages.

1. Identify the smallest search scope: sender, recipient, subject, date range, mailbox, selected Mail.app messages, or exact phrase.
2. Search only local Mail data (`Envelope Index` and downloaded `.emlx`) when the task is read-only. Do not call AppleScript or Computer Use.
3. Open only the most relevant message files needed to answer.
4. Report sender, date, subject, relevant recipients, concise summary, and requested action items.
5. If cached content is missing, report the available metadata and the cache limitation. Ask before opening Mail.app; do not switch to the app automatically.
6. For cleanup or mutation tasks, prepare a candidate list and wait for explicit confirmation before acting.
7. After an approved mutation, verify with a focused re-check.

## Local Mail Data

Mail.app stores downloaded messages under `~/Library/Mail`. Use standard shell tools, Spotlight metadata, SQLite only when clearly needed, and `.emlx` parsing to inspect local messages.

For "not archived" mail counts, default to Inbox messages unless the user defines another mailbox state. Prefer Mail's `Envelope Index` mailbox `total_count` for counts, and mention when downloaded `.emlx` file counts differ.

Useful starting points:

```bash
find ~/Library/Mail -name '*.emlx' -print
mdfind 'kMDItemKind == "Email Message"'
sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index "select sum(total_count) from mailboxes where url like '%/INBOX';"
```

For `.emlx` files, the first line is usually a byte count. Strip it before parsing the MIME message with Python's standard library when the body or headers matter. Do not use broad body `rg` hits as deletion candidates; encoded MIME/base64 content creates many false positives. Prefer parsed headers such as `From:`, `Subject:`, `Date:`, and `Message-ID:`.

## Mail.app API And UI Routing

Use local files and `Envelope Index` exclusively for every ordinary read-only inspection, including message lookup, body reading, search, summaries, recent mail, unread/read mail, verification codes, and mailbox counts. This path must not launch Mail.app and is the default even if cached state may lag the server.

Do not use AppleScript merely to obtain a fresher count or to read messages. If the user asks for the current visible Mail.app state, a currently selected message, a draft, or a mailbox mutation, use native Mail AppleScript through `osascript` for supported Mail object-model operations.

Use Computer Use only when the user explicitly requests reading or manipulating the Mail.app UI, or approves UI access after a cache limitation is reported. This includes visible mailbox rows, toolbar buttons, menus, dialogs, search results, changing selection, and editing or checking a visible draft.

Do not use `System Events`, JXA accessibility scripting, coordinate clicks, or keyboard-event synthesis for Mail.app UI work. Querying Mail's native AppleScript object model is allowed because it is an app API, not UI automation.

Run Mail.app AppleScript commands one at a time and use a short timeout wrapper when probing app state. If Mail.app does not answer quickly, stop and report the automation delay instead of retrying broad commands.

Do not run multiple Mail.app AppleScript or Computer Use commands in parallel. Mail.app can keep a stale message selection or visible smart mailbox list while account mailbox counts have already changed.

Safe examples:

```bash
osascript -e 'tell application "Mail" to count messages of inbox'
```

```bash
osascript -e 'tell application "Mail" to make new outgoing message with properties {visible:true, subject:"Subject", content:"Body"}'
```

For selected messages, AppleScript may read the existing selection before acting. Use Computer Use if the selection itself must be changed or visually verified:

```bash
osascript -e 'tell application "Mail" to get selection'
```

State-changing AppleScript commands must be gated by explicit user confirmation in the conversation. Do not rely on a vague prior instruction when the target set changed.

For account mailbox work, AppleScript's mailbox count is often closer to Mail.app's visible account state than raw `.emlx` file counts. `Envelope Index` is still useful as a final Inbox total check:

```bash
sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index \
  "select sum(total_count), sum(unread_count), sum(deleted_count) from mailboxes where url like '%/INBOX';"
```

`모든 받은 편지함` can display stale conversation rows after a move. Verify with both the account mailbox counts and `Envelope Index`; do not keep archiving stale UI rows if the account Inbox count is already zero. For Gmail, also verify the visible Inbox row list with Computer Use: an AppleScript `move` to `전체보관함` can leave the Gmail Inbox label visible even when the message object appears moved.

To inspect account Inbox counts:

```bash
osascript <<'APPLESCRIPT'
tell application "Mail"
  set configs to {{"iCloud", "INBOX"}, {"Google", "INBOX"}, {"Exchange", "받은 편지함"}, {"Naver", "INBOX"}, {"Kakao", "INBOX"}}
  set rows to {}
  repeat with cfg in configs
    set accName to item 1 of cfg
    set inboxName to item 2 of cfg
    set end of rows to accName & "=" & (count of messages of mailbox inboxName of account accName)
  end repeat
  return rows
end tell
APPLESCRIPT
```

For approved "archive read Inbox except unread" cleanup across accounts, prefer Mail.app's own Archive action or mailbox move over direct database or file edits. Preserve unread messages by `read status is false`; if an unread message was accidentally opened and marked read during UI inspection, preserve it by the previously recorded sender/subject/date. Never click Archive again when the selected visible row is a preserved message.

Move messages by reverse index or repeated index lookup rather than storing a long list of message references; Mail.app references can become stale after moves. Gmail's archive mailbox may be shown as `전체보관함`; if direct string lookup fails because of Unicode normalization, select the mailbox object from the account mailbox list. If Gmail rows remain visible in `모든 받은 편지함` after an AppleScript move, use Computer Use on the Mail.app toolbar Archive button for the specific Gmail Inbox rows, one row at a time, and stop as soon as only preserved rows remain.

For large Archive cleanup by sender, do not make Mail.app scan the whole Archive with a broad `repeat with m in messages of archiveBox` loop. It can hang for minutes. Use `Envelope Index` only to identify candidates and verify counts; never edit the database directly. Then move Mail.app messages by their internal `messages.ROWID`/AppleScript `id` in bounded batches, usually 50-100 ids at a time.

Useful candidate count query:

```bash
sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index \
  "select mb.url, count(*) from messages m
   join mailboxes mb on mb.ROWID=m.mailbox
   left join addresses a on a.ROWID=m.sender
   where mb.url like '%Archive%'
     and lower(a.address) like '%example.com%'
   group by mb.url;"
```

Useful id-list query for a confirmed account/mailbox:

```bash
sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index \
  "select m.ROWID from messages m
   join mailboxes mb on mb.ROWID=m.mailbox
   left join addresses a on a.ROWID=m.sender
   where mb.url='imap://ACCOUNT-ID/Archive'
     and lower(a.address) like '%example.com%'
   order by m.ROWID;"
```

When moving DB-identified candidates, avoid `move targets to trashBox` where `targets` is a filtered AppleScript list. Mail.app can fail with a list-to-specifier coercion error. Move one message at a time by internal id:

```applescript
with timeout of 900 seconds
  tell application "Mail"
    set a to account "iCloud"
    set archiveBox to mailbox "Archive" of a
    set trashBox to mailbox "Deleted Messages" of a
    set idList to {11215, 1738}
    repeat with mid in idList
      try
        set m to item 1 of (messages of archiveBox whose id is mid)
        move m to trashBox
      end try
    end repeat
  end tell
end timeout
```

After a large move, verify by mailbox URL, not by file presence. `.emlx` files can remain as downloaded cache or duplicates:

```bash
sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index \
  "select mb.url, count(*) from messages m
   join mailboxes mb on mb.ROWID=m.mailbox
   left join addresses a on a.ROWID=m.sender
   where (mb.url like '%Archive%' or mb.url like '%Deleted%' or mb.url like '%INBOX%')
     and lower(a.address) like '%example.com%'
   group by mb.url
   order by mb.url;"
```

If a user says a deleted message is still visible, first check the mailbox location. Messages moved to Trash/Deleted still appear in Mail search and in Trash views; that is not the same as remaining in Inbox or Archive.

Example pattern:

```applescript
with timeout of 600 seconds
  tell application "Mail"
    set a to account "Google"
    set inboxBox to mailbox "INBOX" of a
    set archiveBox to item 3 of mailboxes of a -- Gmail 전체보관함 in this local Mail.app
    repeat with i from (count of messages of inboxBox) to 1 by -1
      set m to item i of messages of inboxBox
      if read status of m is true then move m to archiveBox
    end repeat
  end tell
end timeout
```

Common archive mailbox mapping observed locally:

- iCloud: `Archive`
- Google/Gmail: Computer Use on the Mail.app toolbar Archive action is preferred for visible rows; the archive mailbox displays as `전체보관함`
- Exchange: `Archive` with Inbox named `받은 편지함`
- Naver: `Archive`
- Kakao: `Archive`

## Cleanup Tasks

Use conservative filters. Good cleanup candidates include newsletters, ads, delivery notices, and clearly requested senders or subjects. Do not include receipts, finance, security, login, legal, domain, infrastructure, customer, or work-task messages unless the user explicitly names that category.

Cleanup flow:

1. Build a focused candidate list.
2. Exclude Trash/Junk/Spam unless the user asks to inspect them.
3. Present the count and representative subjects.
4. Ask for confirmation.
5. Move to Trash instead of permanently deleting when Mail.app supports it.
6. Verify the remaining count after the move.

## Verification Rules

- For Inbox cleanup, verify `Envelope Index` Inbox totals and account-specific Mail.app Inbox counts.
- For Gmail cleanup, also verify the visible `모든 받은 편지함` row list with Computer Use; Gmail labels can remain visible after mailbox moves.
- For sender cleanup from Archive, verify mailbox URL counts: target sender should be zero in Archive/INBOX and present only in Deleted/Trash unless permanent deletion was explicitly approved.
- If Mail.app search still shows moved messages, report their current mailbox before running another mutation.

## Replying And Drafting

- Draft replies in the user's requested language and tone.
- Include only facts supported by the email thread or user instructions.
- Create a Mail draft through the native AppleScript API when asked. Use Computer Use for any visible draft editing or UI verification.
- Ask for explicit confirmation before sending.
