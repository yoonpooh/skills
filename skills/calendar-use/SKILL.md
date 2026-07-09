---
name: calendar-use
description: Quickly read, search, summarize, and inspect local macOS Calendar events from the read-only Calendar.sqlitedb cache without opening Calendar.app, and use Calendar.app automation only for explicitly requested event creation, editing, deletion, invitations, or UI work. Use when the user asks about calendars, schedules, appointments, meetings, availability, upcoming or past events, event details, calendar cleanup, or Calendar.app.
---

# Calendar Use

## Overview

Use this skill for local macOS Calendar work. For every read-only request, query the on-disk Calendar database without launching, activating, or scripting Calendar.app. Treat the database as a fast local-cache snapshot that may lag account sync. Use Calendar automation only for an explicitly requested state change or UI task.

## Safety

- Treat calendar data as private. Read only the date range, calendars, and event fields needed for the request.
- Never edit `Calendar.sqlitedb` or its WAL/SHM files directly.
- Never launch, activate, or foreground Calendar.app for a read-only request unless the user explicitly asks to use the app.
- Before creating, editing, moving, or deleting an event, show the calendar, title, start/end time, time zone, location, attendees, recurrence, and alerts that will change.
- Ask before deleting events, changing recurring series, bulk editing, or sending/updating invitations.
- Treat attendee changes as external communication. Do not add, remove, or notify attendees without explicit approval.
- If a time, time zone, target calendar, or recurring-event scope is ambiguous, ask before writing.

## Routing

Treat every non-mutating lookup as a database-only task, including schedule checks, availability, title or attendee searches, event details, recent/upcoming events, and summaries.

1. Query `Calendar.sqlitedb` with `sqlite3 -readonly`.
2. Do not call AppleScript or Computer Use during a read-only request.
3. Report that results come from the local Calendar cache and may omit events not synced to this Mac.
4. If the database lacks a requested field or appears stale, report the limitation and ask before opening Calendar.app. Do not switch automatically.
5. For an approved write, use Calendar's native AppleScript object model when it supports the exact operation.
6. Use Computer Use only for explicitly requested Calendar.app UI work or an approved write that the native API cannot perform safely.

## Local Database

The current macOS Calendar cache is:

```bash
DB="$HOME/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"
sqlite3 -readonly "$DB" '.tables'
```

Important tables:

- `CalendarItem`: event title, description, dates, URL, conference URL, calendar, recurrence, status, and invitation fields.
- `OccurrenceCache`: expanded occurrences for recurring and non-recurring events. Use it for date-range and availability queries.
- `Calendar`: calendar title and account/store relationship.
- `Location`: event place and address.
- `Participant`: attendee and organizer metadata.
- `Alarm`: alert timing.

Calendar timestamps use seconds since 2001-01-01. Convert them with:

```sql
datetime(value + 978307200, 'unixepoch', 'localtime')
```

Use `OccurrenceCache` rather than only `CalendarItem.start_date` for schedule queries so recurring occurrences are included. Deduplicate on `event_id` plus `occurrence_date` if joins add repeated rows.

## Read-Only Queries

List upcoming events without opening Calendar.app:

```bash
sqlite3 -readonly -header -column "$DB" "
select datetime(oc.occurrence_date + 978307200, 'unixepoch', 'localtime') as starts_at,
       datetime(oc.occurrence_end_date + 978307200, 'unixepoch', 'localtime') as ends_at,
       ci.all_day,
       ci.summary,
       c.title as calendar,
       coalesce(l.title, l.address, '') as location
from OccurrenceCache oc
join CalendarItem ci on ci.ROWID = oc.event_id
left join Calendar c on c.ROWID = ci.calendar_id
left join Location l on l.ROWID = ci.location_id
where oc.occurrence_end_date >= strftime('%s', 'now') - 978307200
order by oc.occurrence_date
limit 20;"
```

For a requested local date range, use half-open bounds and include events that overlap the range:

```sql
where oc.occurrence_end_date >= strftime('%s', :start_local) - 978307200
  and oc.occurrence_date < strftime('%s', :end_local) - 978307200
```

Search narrowly by title, notes, location, or conference URL and apply a reasonable date bound whenever possible:

```sql
where lower(coalesce(ci.summary, '')) like lower(:pattern)
   or lower(coalesce(ci.description, '')) like lower(:pattern)
   or lower(coalesce(l.title, '')) like lower(:pattern)
```

Do not dump all calendars or full event descriptions when a smaller query answers the request. Present all-day events as dates rather than misleading midnight times. Distinguish event counts from occurrence counts when recurrence is involved.

For availability requests, list overlapping busy events and the free intervals inferred between them. State that declined, canceled, tentative, private, travel-time, and all-day entries may need interpretation; do not silently discard them based on undocumented numeric status flags.

## Writes

Never write to the SQLite database. Use Calendar's native AppleScript API for a confirmed event creation or exact event mutation. Use stable identifiers and the smallest target scope available; titles alone are not unique.

For a new event, resolve all required fields before acting: target calendar, title, start, end or duration, time zone, all-day state, location, notes, recurrence, alerts, and attendees. A direct user request with complete details authorizes creating a private event without attendees; show the final details before executing. Ask separately before invitations or ambiguous recurring changes.

Safe creation shape after details are confirmed:

```applescript
tell application "Calendar"
  tell calendar "Calendar Name"
    make new event with properties {summary:"Title", start date:startDate, end date:endDate}
  end tell
end tell
```

Do not use broad `whose summary is ...` mutations without also matching calendar and time. For recurring events, explicitly distinguish one occurrence from the entire series. After any approved write, verify the exact event through the native API or, when the user requested UI verification, Computer Use.

## Output

- Use the user's local time zone unless another zone is specified.
- Show date, start/end time, title, calendar, and location first; include notes, URL, attendees, alerts, or recurrence only when relevant.
- Mention the local-cache limitation once, not after every event.
- For ambiguous duplicate events, list concise candidates and ask which one the user means before any mutation.
