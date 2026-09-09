---
name: mast-test
description: Use when the user asks to "test mast", "send a test page", "check the pager works", "is mast configured", or "mast status". Reports how the channel is configured and sends one test message. Do not run this on your own; it is for an explicit request.
---

# Test the Mast pager

Paths are relative to this skill's directory.

1. Run `bash scripts/mast-status.sh` and report the result. If no channel is configured, stop
   and point the user at the `mast-setup` skill.
2. Send a test at the priority the user asked for, default `page`:
   `bash scripts/mast-send.sh "Codex test" "sent from $(basename "$PWD")" page --ack`
3. Report the response. `{"ok":true,"id":"mm_…","state":"queued"}` means Mast stored it and
   pushed it; `muted` means the channel is muted or inside quiet hours; `deduped` means the card
   is already on the phone. A 404 means the URL is wrong or the key was rotated more than seven
   days ago. A 429 is the per-key rate limit of 60 sends a minute.
4. If the priority was `page`, tell the user: if the card sounded once and did not repeat, the
   channel's ceiling is `loud` and must be raised to `page` in the Mast app. The 202 does not
   report the clamp, so only the phone can confirm it.
