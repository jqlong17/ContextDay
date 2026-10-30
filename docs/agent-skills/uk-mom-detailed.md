---
id: uk-mom-detailed
title: Detailed MoM
version: 1.0.0
category: uk-meeting
locale: en-GB
---

# Skill: Detailed MoM (UK)

## When to use
User asks for a full minutes-of-meeting from a ContextDay transcript: decisions, actions, and open questions in one pass.

## Data
- Read-only ContextDay SQLite / Agent IO segments for the nominated window
- Prefer `gate_label=speech` text; use `audio_path` only to verify unclear lines
- Do not invent speakers, deadlines, or commitments absent from the transcript

## Hard rules (always)
- Only write verifiable content from the provided ContextDay transcript/context
- Ambiguous commitments marked **TBC**
- No tax/legal conclusions
- External-facing UK English

## Output structure
1. **Title** — meeting topic or user-supplied name  
2. **When** — local timezone range  
3. **Attendees** — only names evidenced in transcript (else omit)  
4. **Decisions** — numbered; each tied to evidence  
5. **Actions** — owner + task + due date if stated; else TBC  
6. **Open questions** — unresolved items still needing an answer  
7. **Notes / evidence** — short verifiable excerpts  

## Channel
Default: local preview (md/txt). Export to Gmail / Docs / Word / file only when the user chooses a channel. **Never** auto-send email.

## Example / Preview
```text
Title: Q3 roadmap sync
When: Tue 14 Oct 2025, 10:00–10:45 (Europe/London)

Decisions
1. Ship beta to the pilot cohort on 28 Oct (agreed by Sam and Priya).

Actions
1. Sam — circulate beta invite list — due Fri 17 Oct
2. Priya — confirm staging capacity — TBC

Open questions
1. Who owns the customer FAQ draft? (mentioned; no owner named)

Notes / evidence
- “We’ll aim for the 28th for the pilot.” — Sam, ~10:18
```
