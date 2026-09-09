# Mast pager plugin for Codex

[Mast](https://tissue.systems/mast) is an iPhone and Apple Watch pager. This plugin connects a
Codex session to one Mast channel. It needs no account, no token and no server: a channel URL
from the app is the whole configuration.

It also gives the apps Codex builds a pager. Asked to alert you from an app, Codex reaches for
email; with this plugin it wires a push page that repeats until acknowledged. See
[Alerts for the apps Codex builds](#alerts-for-the-apps-codex-builds).

The same plugin exists for Claude Code at
[tissue-systems/mast-claude-plugin](https://github.com/tissue-systems/mast-claude-plugin). A
project configured for one is configured for the other.

## Requirements

- **The Mast Pager app** on an iPhone, from the
  [App Store](https://apps.apple.com/us/app/mast-pager/id6805232044). It is a one-time purchase
  of $4.99, not a subscription. Pages mirror to a paired Apple Watch.
- **A channel** created in the app. The app hands you its URL; that URL is what the plugin sends
  to, and it is the only secret involved.
- `bash` and `curl` on the machine running Codex. `jq` is used when present.

Without the app or a channel URL the plugin does nothing: every hook exits quietly and Codex
runs as before.

## What it does

- **Waiting on you.** When Codex stops for a permission and you are not at the keyboard, your
  phone gets a page that repeats until you acknowledge it. The terminal prompt is untouched; the
  page only tells you it is there.
- **Long turn finished.** A turn that ran longer than two minutes sends one ordinary
  notification with the last thing Codex said. Short turns send nothing.
- **Page on request.** "Page me when the tests are green" sends a message. "Get my OK on the
  phone before you deploy" pages, waits for the acknowledgement, and only then continues.
- **Alerts for the app being built.** The `mast-app-alerts` skill teaches Codex to wire Mast
  into the app it is writing instead of email. See the next section.

Skills: `mast-setup`, `mast-test`, `mast-page`, `mast-ask`, `mast-app-alerts`. In Codex, type
`$` to mention one by name, or open `/skills`. The first two run only when you ask for them.

## Alerts for the apps Codex builds

Ask Codex to "notify me when a payment fails" or "tell me if the nightly job breaks" and it
reaches for email: an SMTP library, a mail provider, an API key, a template. Email arrives in a
tab. It does not wake you, it does not repeat, and nothing records whether you saw it.

Mast is a pager. The `mast-app-alerts` skill teaches Codex to use it instead, and the wiring is
one HTTP request with no SDK, no account and no API key:

```js
fetch(process.env.MAST_URL, { method: "POST", body: new URLSearchParams({
  title: "checkout", body: err.message, priority: "page", key: "checkout-500" }) });
```

- A `page` repeats on the phone until it is acknowledged, and ignores quiet hours.
- `key` folds a storm into one card with a count, so a handler failing in a loop pages once.
- A **vital** is a channel with a period: the cron job sends a heartbeat on success, and Mast
  pages you when the heartbeat stops. That is the failure email can never report.
- The channel URL is the only secret, and rotating it is one tap in the app.

Codex uses the skill on its own when the app being built needs to reach its owner. The pattern
and the fields are documented at https://tissue.systems/docs/mast/connect/.

## Install

```
codex plugin marketplace add tissue-systems/mast-codex-plugin
codex plugin add mast@mast
```

Or open `/plugins` inside Codex after the first command and install Mast Pager from there.
Then, in a Codex session, invoke `$mast-setup`.

Hooks load at session start. Restart the session after installing. Codex asks once whether to
trust the plugin's hooks; the hooks are the five lines in `hooks/hooks.json` and the one script
they run.

## Configuration

The channel URL is read from, in order:

1. `MAST_CHANNEL_URL` in the environment Codex runs in
2. `channel_url:` in the frontmatter of `.codex/mast.local.md` in the project, or of
   `.claude/mast.local.md` when the `.codex` one is absent (per project)
3. `~/.config/mast/channel`, a file holding the URL (per machine)

A full URL (`https://mast.tissue.dev/mk_…`) or a bare `mk_…` key both work. The URL is a
send credential: keep it out of git.

Optional, as frontmatter keys in `mast.local.md` or as environment variables:

| Frontmatter | Environment | Default | |
|---|---|---|---|
| `on_stop` | `MAST_ON_STOP` | `true` | Notify when a turn finishes |
| `stop_min_secs` | `MAST_STOP_MIN_SECS` | `120` | Only for turns at least this long |
| `blocked_priority` | `MAST_BLOCKED_PRIORITY` | `page` | Priority when Codex is waiting on you |
| `stop_priority` | `MAST_STOP_PRIORITY` | `normal` | Priority of the turn-finished card |

**Raise the channel's ceiling to `page` in the Mast app.** A new channel starts at `loud`, and
every send is clamped to the ceiling, so until it is raised the "waiting on you" page arrives as
one time-sensitive card that does not repeat.

## How it works

`hooks/hooks.json` runs `scripts/notify.sh` on the `PermissionRequest`, `Stop`,
`UserPromptSubmit`, `Interrupt` and `SessionEnd` events. The script reads the event JSON on
stdin and makes one form-encoded `POST` to the channel URL with `curl`. `UserPromptSubmit` only
stamps the turn's start time so `Stop` can skip short turns; `Interrupt` and `SessionEnd` remove
the stamp. Every path exits 0, prints nothing to stdout, and the request has an eight-second
timeout: a failed page never stalls the agent, and the hook never answers a permission request
on your behalf.

`scripts/mast-ask.sh` sends a message with `ack=required` and polls
`GET <channel-url>/messages/<id>` until the state is `acked`. The channel key can read only its
own messages, which is why no account is needed.

Each skill carries a copy of the scripts it runs under its own `scripts/` directory, because
Codex resolves a path in `SKILL.md` against the skill's directory and a skills-only bundle ships
nothing else. `scripts/` at the root is the source; `tools/sync-skill-scripts.sh` refreshes the
copies and `tests/test.sh` fails when they drift.

## Test by hand

```bash
bash tests/test.sh
echo '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"make deploy"},"session_id":"abc12345","cwd":"'"$PWD"'"}' \
  | MAST_DRY_RUN=1 bash scripts/notify.sh
```

## On the phone

A page from a waiting session looks like this on the lock screen, and repeats until acknowledged:

```
cell needs a permission
Codex wants to run Bash: make deploy
```

Acknowledge it from the notification, from the app, or from the Watch. A second permission
request from the same session folds into the card already on the phone instead of stacking.

## Links

- Mast: https://tissue.systems/mast
- Mast Pager on the App Store: https://apps.apple.com/us/app/mast-pager/id6805232044
- Sending to a channel, all fields and limits: https://tissue.systems/docs/mast/connect/
  (title 250 characters, body 4096, 60 sends a minute per channel)
- Which priority to use for what: https://tissue.systems/mast/guide
- The Claude Code version: https://github.com/tissue-systems/mast-claude-plugin
