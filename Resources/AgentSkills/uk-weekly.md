---
id: uk-weekly
title: Weekly
version: 1.0.0
category: uk-meeting
locale: en-GB
---

# Skill: Weekly progress (UK)

## When to use
User asks to compress **multiple meetings** in one calendar week into a single progress note (not one MoM per meeting).

## Data
- ContextDay speech clusters for the nominated Mon–Sun (local timezone)
- Optional calendar cues if the user supplies them; do not invent events

## Hard rules (always)
- Only write verifiable content from the provided ContextDay transcript/context
- Ambiguous commitments marked **TBC**
- No tax/legal conclusions
- External-facing UK English

## Output structure
1. **Week** — `YYYY/MM/DD–MM/DD` (Mon–Sun local)
2. **Progress this week** — themes / shipped / decided (merged across meetings)
3. **Actions carried** — owners + open items still live
4. **Parked / TBC** — ambiguous commitments
5. **Meetings covered** — short list of windows (date + topic), not full per-meeting minutes

Prefer synthesis over a dump of every agenda item.

## Channel
Default: local preview (md/txt). Export on user-chosen channel later. **Never** auto-send email.

## Example / Preview
```text
Week: 13–19 Oct 2025

Progress this week
- Agreed pilot beta date (28 Oct) across roadmap + eng sync.
- Staging capacity review started; final number still TBC.

Actions carried
- Sam — beta invite list — due 17 Oct
- Priya — staging capacity — TBC

Meetings covered
- Tue 14 Oct · Q3 roadmap sync
- Thu 16 Oct · Eng capacity check-in
```
