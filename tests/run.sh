#!/usr/bin/env bash
# Pruebas de humo: sintaxis, renders con payloads de ejemplo e instalación en una carpeta temporal.
# Corre los scripts con el mismo bash que corre este archivo, así en CI se prueba también /bin/bash 3.2 de macOS.
#
#   bash tests/run.sh
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sh_bin=${BASH:-bash}
passed=0; failed=0

pass() { passed=$((passed + 1)); printf '  ok    %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
strip() { sed $'s/\033\\[[0-9;]*m//g'; }

# render <payload> [VAR=valor ...]: dibuja la statusline sin la configuración del usuario, sin color
render() {
  local payload=$1; shift
  printf '%s' "$payload" | env CLAUDE_STATUSLINE_CONFIG=/dev/null CLAUDE_CONFIG_DIR="$work/claude" COLUMNS=140 "$@" \
    "$sh_bin" "$root/statusline.sh" | strip
}
contains() {
  local name=$1 out=$2 want=$3
  case "$out" in *"$want"*) pass "$name" ;; *) fail "$name" "expected \"$want\" in: $(printf '%s' "$out" | tr '\n' ' ')" ;; esac
}
absent() {
  local name=$1 out=$2 bad=$3
  case "$out" in *"$bad"*) fail "$name" "unexpected \"$bad\" in: $(printf '%s' "$out" | tr '\n' ' ')" ;; *) pass "$name" ;; esac
}

echo "bash $BASH_VERSION"

echo "Syntax"
for f in statusline.sh install.sh tests/run.sh; do
  if "$sh_bin" -n "$root/$f" 2>"$work/err"; then pass "$f"; else fail "$f" "$(cat "$work/err")"; fi
done

echo "Render"
now=$(date +%s)
payload='{"session_id":"s1","model":{"display_name":"Opus 5.5"},"workspace":{"current_dir":"/demo/my-project"},"effort":{"level":"high"},"cost":{"total_cost_usd":3.72,"total_duration_ms":4980000,"total_lines_added":248,"total_lines_removed":61},"context_window":{"used_percentage":35},"prompt_cache":{"hit_ratio":0.91,"warm":true},"rate_limits":{"five_hour":{"used_percentage":43,"resets_at":'$((now + 8040))'},"seven_day":{"used_percentage":67,"resets_at":'$((now + 280000))'}}}'
out=$(render "$payload")
for want in my-project "Opus 5.5" High "Context" "35%" "Today" "Week" "Time 1h 23m" "+248" "Cost \$3.72" "Cache 91%"; do
  contains "p10k shows $want" "$out" "$want"
done
out=$(render "$payload" CLAUDE_STATUSLINE_PRESET=classic)
contains "classic shows the model" "$out" "Opus 5.5"
absent "classic hides cost" "$out" "Cost"
out=$(render "$payload" CLAUDE_STATUSLINE_ICONS=none CLAUDE_STATUSLINE_LAYOUT=compact)
contains "no icons, compact" "$out" "Context"
out=$(render '{}')
[ -n "$out" ] && pass "empty payload renders" || fail "empty payload renders"

# el archivo de configuración nunca se ejecuta
printf 'preset=$(touch %s)\nstyle=`touch %s`\n' "$work/pwned" "$work/pwned" > "$work/evil.conf"
printf '%s' "$payload" | CLAUDE_STATUSLINE_CONFIG="$work/evil.conf" "$sh_bin" "$root/statusline.sh" >/dev/null 2>&1
[ -e "$work/pwned" ] && fail "statusline.conf is never executed" || pass "statusline.conf is never executed"

echo "Install"
# install <carpeta> [flags]: instala desde este checkout, sin preguntas
install() {
  local dir=$1; shift
  CLAUDE_CONFIG_DIR="$dir" "$sh_bin" "$root/install.sh" --no-wizard "$@" </dev/null >"$work/install.log" 2>&1
}
setting() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {}, {"d": d}))' "$@" 2>/dev/null; }

dir="$work/i1"; mkdir -p "$dir"; printf '{"theme":"dark","env":{"FOO":"1"}}' > "$dir/settings.json"
if install "$dir"; then pass "installs into an existing settings.json"; else fail "installs into an existing settings.json" "$(cat "$work/install.log")"; fi
[ "$(setting "$dir/settings.json" 'd["statusLine"]["command"]')" = "bash $dir/statusline.sh" ] && pass "registers the command" || fail "registers the command"
[ "$(setting "$dir/settings.json" 'd["env"]["FOO"] + d["theme"]')" = 1dark ] && pass "keeps other settings" || fail "keeps other settings"

dir="$work/i4"; mkdir -p "$dir"; printf '{"statusLine":{"type":"command","command":"other.sh"}}' > "$dir/settings.json"
install "$dir"; rc=$?
[ "$rc" -eq 2 ] && [ "$(setting "$dir/settings.json" 'd["statusLine"]["command"]')" = other.sh ] \
  && pass "does not replace another statusline without --force" || fail "does not replace another statusline without --force" "exit $rc"

# sin jq, el instalador usa python3: PATH con todo menos jq
nojq="$work/nojq"; mkdir -p "$nojq"
IFS=: read -r -a path_dirs <<< "$PATH"
for d in "${path_dirs[@]}"; do
  for f in "$d"/*; do
    name=${f##*/}
    [ "$name" = jq ] || [ -e "$nojq/$name" ] || { [ -x "$f" ] && ln -s "$f" "$nojq/$name"; }
  done
done 2>/dev/null
PATH="$nojq" command -v jq >/dev/null && fail "jq is hidden from PATH" || pass "jq is hidden from PATH"
dir="$work/i5"; mkdir -p "$dir"; printf '{"env":{"FOO":"1"}}' > "$dir/settings.json"
if PATH="$nojq" install "$dir" && [ "$(setting "$dir/settings.json" 'd["env"]["FOO"] + d["statusLine"]["type"]')" = 1command ]; then
  pass "works with python3 when jq is missing"
else
  fail "works with python3 when jq is missing" "$(cat "$work/install.log")"
fi

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
