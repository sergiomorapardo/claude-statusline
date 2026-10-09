#!/usr/bin/env bash
# Instala claude-statusline: copia el script en la carpeta de Claude Code y lo registra en settings.json.
# Se puede correr varias veces. No reemplaza otra statusline sin --force y hace backup antes de editar.
#
#   curl -fsSL https://raw.githubusercontent.com/sergiomorapardo/claude-statusline/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/sergiomorapardo/claude-statusline/main/install.sh | bash -s -- --force
#
# Códigos de salida: 0 instalado, 1 error, 2 ya hay otra statusline (repetir con --force para reemplazarla).
set -euo pipefail

REPO="sergiomorapardo/claude-statusline"
REF="${CLAUDE_STATUSLINE_REF:-main}"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET="$CONFIG_DIR/statusline.sh"
SETTINGS="$CONFIG_DIR/settings.json"
COMMAND="bash $TARGET"
# con la carpeta por defecto se guarda ~ en la configuración, como en el README
[ "$CONFIG_DIR" = "$HOME/.claude" ] && COMMAND="bash ~/.claude/statusline.sh"

force=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    -h|--help) echo "Usage: install.sh [--force]   (--force replaces another configured statusline)"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

info() { printf '  %s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
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

# 3. instalar el script, con backup si había otra versión
if [ -f "$TARGET" ] && ! cmp -s "$tmp" "$TARGET"; then
  cp "$TARGET" "$TARGET.bak-$stamp"
  info "Backed up the previous script to $TARGET.bak-$stamp"
fi
cp "$tmp" "$TARGET"
chmod +x "$TARGET"
info "Installed $TARGET"

# 4. registrar la statusline en settings.json, conservando el resto de la configuración
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

# 5. comprobar que el script corre con un payload mínimo
if printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"}}' "$PWD" | bash "$TARGET" >/dev/null 2>&1; then
  info "Test render OK"
else
  fail "The statusline did not run. Check $TARGET."
fi

echo "Done. Restart Claude Code or send a message to see it."
echo "Icons need a Nerd Font in your terminal: https://www.nerdfonts.com/"
