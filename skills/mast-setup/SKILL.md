---
name: mast-setup
description: Use when the user asks to "set up mast", "configure the pager", "connect my phone", "where do I put the channel URL", "mast setup", or right after installing the Mast plugin. Walks through getting a channel URL from the Mast app and storing it where the plugin reads it, then sends a test page. Do not run this on your own; it is for an explicit request.
---

# Set up the Mast pager

Mast is an iPhone and Apple Watch pager app. A channel URL is a send credential:
anything that can POST to it can make the owner's phone buzz. This plugin needs one such URL.
Paths below are relative to this skill's directory.

## Steps

1. Run `bash scripts/mast-status.sh`. If it reports a configured channel, skip to step 4.

2. Ask the user for a channel URL, and tell them how to get one if they do not have it:
   - Install Mast Pager from the App Store (https://apps.apple.com/us/app/mast-pager/id6805232044).
   - In the app, create a channel named for this machine or for Codex, and copy its URL.
     It looks like `https://mast.tissue.dev/mk_…`. A bare `mk_…` key is accepted as well.
   - **Raise the channel's ceiling to `page` in the app** (channel settings). Every new channel
     starts with a ceiling of `loud`, and a `loud` card sounds once and stops. Only a `page`
     repeats until acknowledged, which is the whole point of the plugin's "waiting on you" alert.

3. Store it. Offer these, in this order of preference:
   - **Per machine (recommended):** write the URL as the only line of
     `~/.config/mast/channel`, then `chmod 600` it and `chmod 700 ~/.config/mast`. Every
     project on this machine pages the same channel; the card's title names the project.
   - **Per project:** write `.codex/mast.local.md` in the project root with YAML frontmatter
     `channel_url: https://mast.tissue.dev/mk_…`. Confirm `.codex/*.local.md` is in the
     project's `.gitignore` before writing, and add it if not. This wins over the per-machine
     file. A project that already has `.claude/mast.local.md` from the Claude Code plugin
     needs nothing: that file is read too.
   - **Environment:** `MAST_CHANNEL_URL` in the shell Codex runs in. This wins over both files.
   Never write the URL into a file that is committed.

4. Optional settings, all in the same `mast.local.md` frontmatter or as environment
   variables. Mention them; do not set them unless asked.

   | Setting | Env | Default | Meaning |
   |---|---|---|---|
   | `on_stop` | `MAST_ON_STOP` | `true` | Notify when a turn finishes |
   | `stop_min_secs` | `MAST_STOP_MIN_SECS` | `120` | Only notify for turns at least this long |
   | `blocked_priority` | `MAST_BLOCKED_PRIORITY` | `page` | Priority when Codex is waiting on the human |
   | `stop_priority` | `MAST_STOP_PRIORITY` | `normal` | Priority for the turn-finished card |

5. Send a test: run `bash scripts/mast-send.sh "Codex" "Mast is set up on $(hostname)" page --ack`.
   Ask the user whether the card repeated. If it arrived once and went quiet, the channel's
   ceiling is still `loud`; point them back to step 2.

6. Explain what happens from here in two sentences: a permission request pages the phone and
   repeats until acknowledged; a turn that ran longer than two minutes sends one ordinary
   notification when it ends. Hooks load at session start, so a fresh install needs the
   session restarted, and Codex asks once to trust the plugin's hooks.
