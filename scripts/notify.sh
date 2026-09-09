#!/usr/bin/env bash
# Hook handler. Codex runs this with the hook event as JSON on stdin and
# waits for nothing: every path exits 0, prints nothing to stdout, and the HTTP
# call has a hard timeout. A failed page must never stall or block the agent.
#
# Events and what they become on the phone:
#   PermissionRequest   page   — Codex is waiting for you to approve a tool call
#   Stop                normal — the turn finished (only after a long turn)
#   UserPromptSubmit    —      — stamps the turn start, sends nothing
#   Interrupt           —      — removes the stamp (you are at the keyboard)
#   SessionEnd          —      — removes the stamp
#
# The dedupe key is per session and per kind, so a burst of permission
# requests from one session folds into the card that is already on the phone.
# Stdout stays empty on purpose: a PermissionRequest hook that prints JSON
# would be read as a decision, and the terminal prompt stays the authority.

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

input="$(cat)"
field() { printf '%s' "$input" | mast_json_field "$1"; }
nested() { printf '%s' "$input" | mast_json_nested "$1" "$2"; }

event="$(field hook_event_name)"
session="$(field session_id)"
cwd="$(field cwd)"
[[ -n "$cwd" ]] || cwd="$PWD"
project="$(basename "$cwd")"
short_session="${session:0:8}"

# Turn stamps: the Stop hook fires after every turn, including a two-second
# one while the user is sitting at the terminal. Only a turn that ran at
# least stop_min_secs is worth a notification.
stamp_dir="${TMPDIR:-/tmp}/mast-codex-${UID:-$(id -u)}"
stamp="${stamp_dir}/${session:-nosession}.start"

case "$event" in
  UserPromptSubmit)
    mkdir -p "$stamp_dir" 2>/dev/null && chmod 700 "$stamp_dir" 2>/dev/null
    date +%s > "$stamp" 2>/dev/null
    exit 0 ;;
  Interrupt|SessionEnd)
    rm -f "$stamp" 2>/dev/null
    exit 0 ;;
esac

url="$(mast_channel_url "$cwd")" || exit 0   # not configured: silently do nothing

# Settings (env wins, then the project's mast.local.md, then the default).
setting() {  # setting <ENV_NAME> <yaml_key> <default>
  local v="${!1:-}"
  [[ -n "$v" ]] || v="$(mast_setting "$2" "$cwd")"
  printf '%s' "${v:-$3}"
}
on_stop="$(setting MAST_ON_STOP on_stop true)"
stop_min="$(setting MAST_STOP_MIN_SECS stop_min_secs 120)"
blocked_priority="$(setting MAST_BLOCKED_PRIORITY blocked_priority page)"
stop_priority="$(setting MAST_STOP_PRIORITY stop_priority normal)"

title="" body="" priority="" key="" extra=()

case "$event" in
  PermissionRequest)
    tool="$(field tool_name)"
    what="$(nested tool_input description | mast_truncate 300)"
    [[ -n "$what" ]] || what="$(nested tool_input command | mast_truncate 300)"
    title="$project needs a permission"
    if [[ -n "$what" ]]; then
      body="Codex wants to run ${tool:-a tool}: $what"
    else
      body="Codex is waiting for you to approve ${tool:-a tool call}."
    fi
    priority="$blocked_priority"
    key="codex-${short_session}-blocked"
    extra+=("ack=required") ;;

  Stop)
    [[ "$on_stop" == "true" || "$on_stop" == "1" || "$on_stop" == "on" ]] || exit 0
    # stop_hook_active means a Stop hook already continued this turn once;
    # do not page twice for one turn.
    [[ "$(field stop_hook_active)" == "true" ]] && exit 0
    if [[ -f "$stamp" ]]; then
      started="$(cat "$stamp" 2>/dev/null || echo 0)"
      elapsed=$(( $(date +%s) - ${started:-0} ))
      (( elapsed >= stop_min )) || exit 0
    else
      # No stamp: an older session, or the stamp dir is unwritable. Without a
      # duration to judge, stay quiet rather than buzz on every short turn.
      exit 0
    fi
    last="$(field last_assistant_message | mast_truncate 400)"
    mins=$(( elapsed / 60 ))
    title="$project finished"
    body="${last:-Codex finished a ${mins}-minute turn.}"
    priority="$stop_priority"
    key="codex-${short_session}-stop"
    rm -f "$stamp" 2>/dev/null ;;

  *) exit 0 ;;
esac

if [[ "${MAST_DRY_RUN:-}" == "1" ]]; then
  printf 'POST %s\n  title=%s\n  body=%s\n  priority=%s\n  key=%s\n' \
    "$url" "$title" "$body" "$priority" "$key" >&2
  for f in "${extra[@]+"${extra[@]}"}"; do printf '  %s\n' "$f" >&2; done
  exit 0
fi

mast_send "$url" "title=$title" "body=$body" "priority=$priority" "key=$key" \
  "${extra[@]+"${extra[@]}"}" >/dev/null 2>&1 || true
exit 0
