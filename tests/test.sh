#!/usr/bin/env bash
# Offline checks: manifests parse, skill copies of the scripts match the
# source, the hook script turns each Codex event into the right card, and the
# URL normaliser accepts every documented spelling. No network.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }

for f in plugin.json .codex-plugin/plugin.json .agents/plugins/marketplace.json hooks/hooks.json; do
  python3 -c "import json,sys; json.load(open('$f'))" 2>/dev/null && ok "$f parses" || bad "$f parses"
done
python3 - <<'PY' && ok "interface limits" || bad "interface limits"
import json
i = json.load(open("plugin.json"))["extensions"]["com.openai"]["interface"]
assert len(i["displayName"]) <= 30 and len(i["shortDescription"]) <= 30
assert len(i["longDescription"]) <= 4000 and len(i["developerName"]) <= 80
assert len(i["defaultPrompt"]) <= 3 and all(len(p) <= 128 for p in i["defaultPrompt"])
assert json.load(open(".codex-plugin/plugin.json"))["interface"] == i
PY

for d in skills/*/; do
  [[ -f "$d/SKILL.md" ]] || { bad "$d has SKILL.md"; continue; }
  head -1 "$d/SKILL.md" | grep -q '^---$' || bad "$d frontmatter"
  grep -q '^name: ' "$d/SKILL.md" && grep -q '^description: ' "$d/SKILL.md" && ok "$d frontmatter" || bad "$d frontmatter"
  for s in "$d"scripts/*.sh; do
    [[ -e "$s" ]] || continue
    cmp -s "$s" "scripts/$(basename "$s")" && ok "$s matches source" || bad "$s drifted from scripts/ (run tools/sync-skill-scripts.sh)"
  done
done
grep -rn 'CLAUDE_PLUGIN\|/mast:' scripts skills hooks >/dev/null && bad "Claude-only references left" || ok "no Claude-only references"

# Keep the developer's own ~/.config/mast out of the results.
cfg="$(mktemp -d)"
export HOME="$cfg" XDG_CONFIG_HOME="$cfg/.config"
mkdir -p "$XDG_CONFIG_HOME/mast"
unset MAST_ALLOWED_HOSTS MAST_STOP_MIN_SECS

# lib: URL normalisation
. scripts/lib.sh
t() { local got; got="$(MAST_CHANNEL_URL="$1" mast_channel_url)"; [[ "$got" == "$2" ]] && ok "url $1" || bad "url $1 -> $got"; }
t "mk_abc" "https://mast.tissue.dev/mk_abc"
t "https://mast.tissue.dev/m/mk_abc" "https://mast.tissue.dev/mk_abc"
t "https://mast.tissue.dev/mk_abc/" "https://mast.tissue.dev/mk_abc"
t " https://mast.tissue.dev/mk_abc " "https://mast.tissue.dev/mk_abc"
refuse() { ( MAST_CHANNEL_URL="$1" mast_channel_url >/dev/null ) && bad "refuses $1" || ok "refuses $1"; }
refuse "ftp://x"
refuse "http://mast.tissue.dev/mk_abc"
refuse "https://evil.example/mk_abc"
refuse "https://mast.tissue.dev@evil.example/mk_abc"
refuse "https://mast.tissue.dev.evil.example/mk_abc"
[[ "$(MAST_ALLOWED_HOSTS="mast.example" MAST_CHANNEL_URL=https://mast.example/mk_x mast_channel_url)" == "https://mast.example/mk_x" ]] \
  && ok "MAST_ALLOWED_HOSTS admits a host" || bad "MAST_ALLOWED_HOSTS"
mast_valid_setting stop_min_secs 'HOME[$(id)]' && bad "rejects a hostile stop_min_secs" || ok "rejects a hostile stop_min_secs"

# settings file precedence
tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude" "$tmp/.codex"
printf -- '---\nchannel_url: mk_claude\n---\n' > "$tmp/.claude/mast.local.md"
[[ "$(MAST_CHANNEL_URL= mast_channel_url "$tmp")" == "https://mast.tissue.dev/mk_claude" ]] && ok "reads .claude/mast.local.md" || bad "reads .claude/mast.local.md"
printf -- '---\nchannel_url: "mk_codex"\nstop_min_secs: 7\n---\n' > "$tmp/.codex/mast.local.md"
[[ "$(MAST_CHANNEL_URL= mast_channel_url "$tmp")" == "https://mast.tissue.dev/mk_codex" ]] && ok ".codex wins over .claude" || bad ".codex wins over .claude"
[[ "$(mast_setting stop_min_secs "$tmp")" == "7" ]] && ok "reads a setting" || bad "reads a setting"
echo "mk_machine" > "$XDG_CONFIG_HOME/mast/channel"
[[ "$(MAST_CHANNEL_URL= mast_channel_url "$tmp")" == "https://mast.tissue.dev/mk_machine" ]] && ok "per-machine channel wins over the project" || bad "machine vs project"
rm "$XDG_CONFIG_HOME/mast/channel"
printf -- '---\nstop_min_secs: 300\n---\n' > "$XDG_CONFIG_HOME/mast/settings.md"
[[ "$(mast_setting stop_min_secs "$tmp")" == "300" ]] && ok "settings.md wins over the project" || bad "settings.md vs project"
rm "$XDG_CONFIG_HOME/mast/settings.md"
if command -v git >/dev/null 2>&1; then
  git -C "$tmp" init -q && git -C "$tmp" add .codex/mast.local.md
  ( MAST_CHANNEL_URL= mast_channel_url "$tmp" >/dev/null ) && bad "ignores a git-tracked project file" || ok "ignores a git-tracked project file"
  rm -rf "$tmp/.git"
fi

# hostile values never reach arithmetic
pwn="$tmp/pwned"; proj="$tmp/hostile"; mkdir -p "$proj/.codex" "$tmp/mast-codex-$(id -u)"
printf -- '---\nchannel_url: mk_project\nstop_min_secs: HOME[$(touch %s)]\n---\n' "$pwn" > "$proj/.codex/mast.local.md"
echo 0 > "$tmp/mast-codex-$(id -u)/h1.start"
printf '%s' '{"hook_event_name":"Stop","session_id":"h1","cwd":"'"$proj"'"}' | MAST_DRY_RUN=1 TMPDIR="$tmp" MAST_CHANNEL_URL= bash scripts/notify.sh >/dev/null 2>&1
[[ ! -e "$pwn" ]] && ok "hostile stop_min_secs runs nothing" || bad "stop_min_secs injection ran"
printf 'HOME[$(touch %s)]' "$pwn" > "$tmp/mast-codex-$(id -u)/h2.start"
printf '%s' '{"hook_event_name":"Stop","session_id":"h2","cwd":"'"$proj"'"}' | MAST_DRY_RUN=1 TMPDIR="$tmp" MAST_CHANNEL_URL= bash scripts/notify.sh >/dev/null 2>&1
[[ ! -e "$pwn" ]] && ok "hostile stamp runs nothing" || bad "stamp injection ran"
printf -- '---\nchannel_url: https://evil.example/mk_x\n---\n' > "$proj/.codex/mast.local.md"
out="$(printf '%s' '{"hook_event_name":"PermissionRequest","session_id":"h3","cwd":"'"$proj"'","tool_name":"Bash"}' | MAST_DRY_RUN=1 TMPDIR="$tmp" MAST_CHANNEL_URL= bash scripts/notify.sh 2>&1 >/dev/null)"
[[ -z "$out" ]] && ok "project file can't point the hook at another host" || bad "redirect: $out"

# hook script, dry run
export MAST_DRY_RUN=1 MAST_CHANNEL_URL=mk_test TMPDIR="$tmp"
run() { printf '%s' "$1" | bash scripts/notify.sh 2>&1 >/dev/null; }
out="$(run '{"hook_event_name":"PermissionRequest","session_id":"abcdef1234","cwd":"/x/proj","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"Clean the build dir"}}')"
grep -q 'title=proj needs a permission' <<<"$out" && grep -q 'Clean the build dir' <<<"$out" && grep -q 'priority=page' <<<"$out" && grep -q 'key=codex-abcdef12-blocked' <<<"$out" && grep -q 'ack=required' <<<"$out" && ok "PermissionRequest pages with ack" || bad "PermissionRequest: $out"
out="$(run '{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/x/proj","tool_name":"Bash","tool_input":{"command":"make test"}}')"
grep -q 'run Bash: make test' <<<"$out" && ok "PermissionRequest falls back to command" || bad "PermissionRequest command: $out"
out="$(run '{"hook_event_name":"Stop","session_id":"s2","cwd":"/x/proj","last_assistant_message":"done"}')"
[[ -z "$out" ]] && ok "Stop without stamp is silent" || bad "Stop without stamp: $out"
run '{"hook_event_name":"UserPromptSubmit","session_id":"s3","cwd":"/x/proj","prompt":"go"}' >/dev/null
[[ -f "$tmp/mast-codex-$(id -u)/s3.start" ]] && ok "UserPromptSubmit stamps" || bad "UserPromptSubmit stamp"
out="$(run '{"hook_event_name":"Stop","session_id":"s3","cwd":"/x/proj","last_assistant_message":"done"}')"
[[ -z "$out" ]] && ok "Stop after a short turn is silent" || bad "short Stop: $out"
echo 0 > "$tmp/mast-codex-$(id -u)/s3.start"
out="$(run '{"hook_event_name":"Stop","session_id":"s3","cwd":"/x/proj","stop_hook_active":false,"last_assistant_message":"Tests green, deployed."}')"
grep -q 'title=proj finished' <<<"$out" && grep -q 'body=Tests green, deployed.' <<<"$out" && grep -q 'priority=normal' <<<"$out" && ok "Stop after a long turn notifies" || bad "long Stop: $out"
[[ ! -f "$tmp/mast-codex-$(id -u)/s3.start" ]] && ok "Stop clears the stamp" || bad "Stop stamp left"
run '{"hook_event_name":"UserPromptSubmit","session_id":"s4","cwd":"/x/proj"}' >/dev/null
run '{"hook_event_name":"Interrupt","session_id":"s4","cwd":"/x/proj"}' >/dev/null
[[ ! -f "$tmp/mast-codex-$(id -u)/s4.start" ]] && ok "Interrupt clears the stamp" || bad "Interrupt stamp left"
out="$(run '{"hook_event_name":"Stop","session_id":"s5","cwd":"/x/proj","stop_hook_active":true}')"
[[ -z "$out" ]] && ok "stop_hook_active is silent" || bad "stop_hook_active: $out"
out="$(MAST_CHANNEL_URL= HOME="$tmp" XDG_CONFIG_HOME="$tmp/none" run '{"hook_event_name":"PermissionRequest","session_id":"s6","cwd":"/nowhere","tool_name":"Bash"}')"
[[ -z "$out" ]] && ok "unconfigured is silent" || bad "unconfigured: $out"
out="$(printf '{"hook_event_name":"PermissionRequest","session_id":"s7","cwd":"/x/p","tool_name":"Bash"}' | bash scripts/notify.sh 2>/dev/null)"
[[ -z "$out" ]] && ok "stdout stays empty (no decision JSON)" || bad "stdout: $out"
rm -rf "$tmp" "$cfg"
[[ $fail -eq 0 ]] && echo "all passed" || { echo "FAILED"; exit 1; }
