#!/usr/bin/env bash
# Instala claude-statusline: copia el script en la carpeta de Claude Code y lo registra en settings.json.
# Se puede correr varias veces. No reemplaza otra statusline sin --force y hace backup antes de editar.
# En una terminal pregunta el estilo paso a paso, como el asistente de Powerlevel10k; sin terminal (por
# ejemplo, desde un agente) usa los flags y no pregunta nada.
#
#   curl -fsSL https://raw.githubusercontent.com/sergiomorapardo/claude-statusline/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/sergiomorapardo/claude-statusline/main/install.sh | bash -s -- --preset classic
#
# Códigos de salida: 0 instalado, 1 error, 2 ya hay otra statusline (repetir con --force para reemplazarla).
set -euo pipefail

REPO="sergiomorapardo/claude-statusline"
REF="${CLAUDE_STATUSLINE_REF:-main}"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET="$CONFIG_DIR/statusline.sh"
SETTINGS="$CONFIG_DIR/settings.json"
CONF="$CONFIG_DIR/statusline.conf"
COMMAND="bash $TARGET"
# con la carpeta por defecto se guarda ~ en la configuración, como en el README
[ "$CONFIG_DIR" = "$HOME/.claude" ] && COMMAND="bash ~/.claude/statusline.sh"

usage() {
  cat <<'EOF'
Usage: install.sh [options]

  --force                Replace another statusline that is already configured
  --configure            Ask the style questions again (needs a terminal)
  --no-wizard            Never ask questions; use the flags and the saved configuration

Style (saved to statusline.conf; options you leave out keep their saved value):
  --preset   p10k | classic
  --icons    nerd | none
  --style    round | angled | flat
  --layout   full | compact
  --segments all | comma-separated list of:
             project,rename,branch,pr,model,effort,context,today,week,time,lines,cost,cache
  --bar      shade | line | block | none
  --colors   vivid | soft
  --gap      line | none
EOF
}

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# valores permitidos de cada opción de estilo
KEYS="preset icons style layout segments bar colors gap"
SEGMENTS="project rename branch pr model effort context today week time lines cost cache"
allowed() {
  case "$1" in
    preset) echo "p10k classic" ;;  icons) echo "nerd none" ;;       style) echo "round angled flat" ;;
    layout) echo "full compact" ;;  bar) echo "shade line block none" ;; colors) echo "vivid soft" ;;
    gap) echo "line none" ;;
  esac
}
valid() {
  local key=$1 value=$2 v
  if [ "$key" = segments ]; then
    [ "$value" = all ] && return 0
    [ -n "$value" ] || return 1
    for v in $(echo "$value" | tr ',' ' '); do
      case " $SEGMENTS " in *" $v "*) ;; *) return 1 ;; esac
    done
    return 0
  fi
  case " $(allowed "$key") " in *" $value "*) return 0 ;; esac
  return 1
}

force=0; configure=0; no_wizard=0; flags=0
for key in $KEYS; do eval "opt_$key=''"; done
while [ $# -gt 0 ]; do
  arg=$1; value=""
  case "$arg" in --*=*) value=${arg#*=}; arg=${arg%%=*} ;; esac
  case "$arg" in
    --force) force=1 ;;
    --configure) configure=1 ;;
    --no-wizard) no_wizard=1 ;;
    -h|--help) usage; exit 0 ;;
    --preset|--icons|--style|--layout|--segments|--bar|--colors|--gap)
      key=${arg#--}
      if [ -z "$value" ]; then
        [ $# -ge 2 ] || fail "$arg needs a value. Run with --help to see the options."
        value=$2; shift
      fi
      valid "$key" "$value" || fail "Invalid value for $arg: $value. Run with --help to see the options."
      eval "opt_$key=\$value"; flags=1 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

info() { printf '  %s\n' "$*"; }
stamp=$(date +%Y%m%d-%H%M%S)

echo "Installing claude-statusline into $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

# herramienta para leer y escribir JSON: jq o, si no está, python3
if command -v jq >/dev/null 2>&1; then json=jq
elif command -v python3 >/dev/null 2>&1; then json=python3
else fail "jq or python3 is required to edit settings.json. Follow the manual install in the README."
fi

# lee settings.json: el comando actual de la statusline (vacío si no hay) o error si el JSON no es válido
current_command() {
  if [ "$json" = jq ]; then
    jq -er 'if type == "object" then (.statusLine.command // "") else error("not an object") end' "$SETTINGS"
  else
    python3 - "$SETTINGS" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if not isinstance(data, dict):
    sys.exit(1)
print((data.get("statusLine") or {}).get("command", ""))
PY
  fi
}

# 1. revisar settings.json antes de tocar nada
existing=""
if [ -s "$SETTINGS" ]; then
  existing=$(current_command 2>/dev/null) || fail "$SETTINGS is not valid JSON. Fix it and run the installer again."
fi
case "$existing" in
  ""|"$COMMAND"|"bash $TARGET") ;;
  *)
    if [ "$force" -eq 0 ]; then
      echo "A different statusline is already configured:" >&2
      echo "  $existing" >&2
      echo "Nothing was changed. Run again with --force to replace it (settings.json is backed up first)." >&2
      exit 2
    fi
    ;;
esac

# 2. obtener el script: del clon local si el instalador corre desde el repo, o de GitHub
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
# con curl | bash no hay archivo de origen y siempre se descarga
src="${BASH_SOURCE[0]:-}"
src_dir=""; [ -f "$src" ] && src_dir=$(cd "$(dirname "$src")" && pwd)
if [ -n "$src_dir" ] && [ -f "$src_dir/statusline.sh" ]; then
  cp "$src_dir/statusline.sh" "$tmp"
  info "Using statusline.sh from $src_dir"
else
  command -v curl >/dev/null 2>&1 || fail "curl is required to download the statusline."
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/statusline.sh" -o "$tmp" \
    || fail "Could not download statusline.sh from $REPO@$REF."
  info "Downloaded statusline.sh from $REPO@$REF"
fi
bash -n "$tmp" || fail "The downloaded script has syntax errors. Nothing was changed."

# 3. estilo: configuración guardada, flags y, en una terminal, el asistente
for key in $KEYS; do eval "cfg_$key=''"; done
if [ -f "$CONF" ]; then
  while IFS='=' read -r key value || [ -n "$key" ]; do
    case " $KEYS " in *" $key "*) valid "$key" "$value" && eval "cfg_$key=\$value" ;; esac
  done < "$CONF"
fi
for key in $KEYS; do
  eval "value=\$opt_$key"
  [ -n "$value" ] && eval "cfg_$key=\$value"
done

# el asistente necesita una terminal: con curl | bash las respuestas se leen de /dev/tty
has_tty=0
if [ -t 1 ] && { : </dev/tty; } 2>/dev/null; then has_tty=1; fi
[ "$configure" -eq 1 ] && [ "$has_tty" -eq 0 ] && fail "--configure needs a terminal. Use the style flags instead (see --help)."
wizard=0
if [ "$no_wizard" -eq 0 ] && [ "$has_tty" -eq 1 ]; then
  { [ "$configure" -eq 1 ] || { [ ! -f "$CONF" ] && [ "$flags" -eq 0 ]; }; } && wizard=1
fi

if [ "$wizard" -eq 1 ]; then
  # ancho real de la terminal, medido en cada vista previa por si se redimensiona la ventana:
  # tput dentro de $( ) no la ve y devuelve 80, stty sí
  measure() {
    cols=$(stty size </dev/tty 2>/dev/null | cut -d' ' -f2)
    case "$cols" in ""|*[!0-9]*|0) cols=${COLUMNS:-100} ;; esac
  }
  now=$(date +%s)
  demo='{"model":{"display_name":"Opus 5.5"},"workspace":{"current_dir":"/demo/my-project"},"pr":{"number":42,"review_state":"approved"},"effort":{"level":"high"},"cost":{"total_cost_usd":3.72,"total_duration_ms":4980000,"total_lines_added":248,"total_lines_removed":61},"context_window":{"used_percentage":35},"prompt_cache":{"hit_ratio":0.91,"warm":true},"rate_limits":{"five_hour":{"used_percentage":43,"resets_at":'$((now + 8040))'},"seven_day":{"used_percentage":67,"resets_at":'$((now + 280000))'}}}'

  # dibuja la statusline de ejemplo con el estilo elegido hasta ahora y, opcionalmente, una opción más
  preview() {
    local overrides="" key value
    for key in $KEYS; do
      eval "value=\$w_$key"
      [ -n "$value" ] && overrides="$overrides CLAUDE_STATUSLINE_$(echo "$key" | tr '[:lower:]' '[:upper:]')=$value"
    done
    [ -n "${1:-}" ] && overrides="$overrides CLAUDE_STATUSLINE_$(echo "$1" | tr '[:lower:]' '[:upper:]')=$2"
    measure
    # shellcheck disable=SC2086
    printf '%s' "$demo" | env CLAUDE_STATUSLINE_CONFIG=/dev/null COLUMNS="$cols" $overrides bash "$tmp"
    printf '\n'
  }
  header() {
    printf '\033[2J\033[H'
    printf '\033[1mclaude-statusline configuration\033[0m   (r) restart  (q) quit\n\n'
    [ -n "${1:-}" ] && printf '\033[1m%s\033[0m\n\n' "$1"
    return 0
  }
  # lee una respuesta válida de la terminal; r reinicia y q sale sin cambios
  answer=""
  ask() {
    local valid_answers=" $1 " reply
    while :; do
      printf '\nChoice [%s]: ' "$(echo "$1" | tr ' ' '/')"
      IFS= read -r reply </dev/tty || reply=q
      case "$reply" in
        q|Q) printf '\nNothing was changed.\n'; exit 0 ;;
        r|R) answer=restart; return ;;
      esac
      case "$valid_answers" in *" $reply "*) answer=$reply; return ;; esac
    done
  }
  # pregunta con una vista previa por opción: choose <clave> <título> <valor:etiqueta>...
  choose() {
    local key=$1 title=$2 i=1 opts="" item
    shift 2
    header "$title"
    for item in "$@"; do
      printf '(%s) %s\n' "$i" "${item#*:}"
      preview "$key" "${item%%:*}"
      printf '\n'
      opts="$opts $i"; i=$((i + 1))
    done
    ask "${opts# }"
    [ "$answer" = restart ] && return 1
    i=1
    for item in "$@"; do
      [ "$answer" = "$i" ] && eval "w_$key=\${item%%:*}"
      i=$((i + 1))
    done
    return 0
  }

  while :; do
    for key in $KEYS; do eval "w_$key=''"; done
    header "Does this look like an apple, a brain and a timer?"
    printf '    \033[1m\xef\x85\xb9   \xf3\xb0\xa7\x91   \xf3\xb0\x94\x9b\033[0m\n'
    printf '\n(y) Yes\n(n) No: the terminal font has no icons. Install a Nerd Font for the full look:\n    https://www.nerdfonts.com/\n'
    ask "y n"; [ "$answer" = restart ] && continue
    [ "$answer" = n ] && w_icons=none

    choose preset "Choose a starting point" "p10k:Powerline: project, usage and session on separate lines (default)" "classic:Classic: compact, pills one after another" || continue
    header "Customize it?"
    preview
    printf '\n(y) Yes, step by step\n(n) No, use this one\n'
    ask "y n"; [ "$answer" = restart ] && continue
    if [ "$answer" = y ]; then
      if [ "$w_icons" != none ]; then
        choose style "Pill ends" "round:Round" "angled:Angled" "flat:Flat" || continue
      fi
      choose layout "Layout" "full:Full: project, usage and session on separate lines" "compact:Compact: pills one after another, wrapping when they do not fit" || continue
      choose bar "Usage bars" "shade:Shaded" "line:Line" "block:Blocks" "none:No bar, only the percentage" || continue
      choose colors "Colors" "vivid:Vivid" "soft:Soft" || continue
      if [ "$w_layout" != compact ] && { [ -n "$w_layout" ] || [ "$w_preset" != classic ]; }; then
        choose gap "Fill the space between pills" "line:With a line" "none:Empty" || continue
      fi

      # segmentos: se ocultan escribiendo sus números
      header "Segments"
      preview
      printf '\n'
      i=1; current=${w_segments:-}
      [ -z "$current" ] && [ "$w_preset" = classic ] && current="project model context today week"
      [ -z "$current" ] && current=$SEGMENTS
      current=" $(echo "$current" | tr ',' ' ') "
      for s in $SEGMENTS; do
        mark="[ ]"; case "$current" in *" $s "*) mark="[x]" ;; esac
        printf '%2s %s %s\n' "$i" "$mark" "$s"; i=$((i + 1))
      done
      restart=0
      while :; do
        printf '\nNumbers to show or hide, separated by spaces (Enter to keep them as they are): '
        IFS= read -r reply </dev/tty || reply=q
        case "$reply" in q|Q) printf '\nNothing was changed.\n'; exit 0 ;; r|R) restart=1; break ;; esac
        ok=1
        for n in $reply; do
          case "$n" in *[!0-9]*|"") ok=0 ;; *) [ "$n" -ge 1 ] && [ "$n" -le 13 ] || ok=0 ;; esac
        done
        [ "$ok" -eq 1 ] && break
      done
      [ "$restart" -eq 1 ] && continue
      i=1; list=""
      for s in $SEGMENTS; do
        on=0; case "$current" in *" $s "*) on=1 ;; esac
        for n in $reply; do [ "$n" -eq "$i" ] && on=$((1 - on)); done
        [ "$on" -eq 1 ] && list="$list,$s"
        i=$((i + 1))
      done
      [ -n "$list" ] && w_segments=${list#,}
    fi

    header "This is your statusline"
    preview
    printf '\n(y) Save and install\n'
    ask "y"; [ "$answer" = restart ] && continue
    break
  done
  printf '\033[2J\033[H'
  for key in $KEYS; do eval "cfg_$key=\$w_$key"; done
fi

# 4. instalar el script, con backup si había otra versión
if [ -f "$TARGET" ] && ! cmp -s "$tmp" "$TARGET"; then
  cp "$TARGET" "$TARGET.bak-$stamp"
  info "Backed up the previous script to $TARGET.bak-$stamp"
fi
cp "$tmp" "$TARGET"
chmod +x "$TARGET"
info "Installed $TARGET"

# 5. guardar el estilo (solo las opciones elegidas; el resto sale del preset)
styled=0
for key in $KEYS; do eval "[ -n \"\$cfg_$key\" ]" && styled=1; done
if [ "$styled" -eq 1 ]; then
  [ -f "$CONF" ] && cp "$CONF" "$CONF.bak-$stamp"
  {
    echo "# claude-statusline style. Change it with: install.sh --configure (or the style flags, see --help)"
    for key in $KEYS; do eval "value=\$cfg_$key"; [ -n "$value" ] && echo "$key=$value"; done
  } > "$CONF"
  info "Saved the style to $CONF"
fi

# 6. registrar la statusline en settings.json, conservando el resto de la configuración
if [ -s "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-$stamp"
  info "Backed up settings.json to $SETTINGS.bak-$stamp"
fi
new=$(mktemp)
if [ "$json" = jq ]; then
  { [ -s "$SETTINGS" ] && cat "$SETTINGS" || echo '{}'; } \
    | jq --arg cmd "$COMMAND" '.statusLine = {type: "command", command: $cmd, padding: 0, refreshInterval: 2}' > "$new"
else
  python3 - "$SETTINGS" "$COMMAND" > "$new" <<'PY'
import json, os, sys
path, cmd = sys.argv[1], sys.argv[2]
data = json.load(open(path)) if os.path.exists(path) and os.path.getsize(path) else {}
data["statusLine"] = {"type": "command", "command": cmd, "padding": 0, "refreshInterval": 2}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
fi
mv "$new" "$SETTINGS"
info "Registered the statusline in $SETTINGS"

# 7. comprobar que el script corre con un payload mínimo
if printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"}}' "$PWD" | bash "$TARGET" >/dev/null 2>&1; then
  info "Test render OK"
else
  fail "The statusline did not run. Check $TARGET."
fi

echo "Done. Restart Claude Code or send a message to see it."
echo "Icons need a Nerd Font in your terminal: https://www.nerdfonts.com/"
