#!/usr/bin/env bash
input=$(cat)

val() { echo "$input" | grep -o "\"$1\":[^,}]*" | head -1 | sed 's/.*://;s/"//g;s/^ *//'; }
nested() { echo "$input" | grep -o "\"$1\":{[^}]*}" | head -1 | grep -o "\"$2\":[^,}]*" | head -1 | sed 's/.*://;s/"//g;s/^ *//'; }
# like nested(), but tolerates one level of sub-objects inside the target object
nested2() { echo "$input" | grep -oE "\"$1\":\{([^{}]|\{[^{}]*\})*\}" | head -1 | grep -o "\"$2\":[^,}]*" | head -1 | sed 's/.*://;s/"//g;s/^ *//'; }

round() { [ -n "$1" ] && [ "$1" != "null" ] && printf "%.0f" "$1" 2>/dev/null; }

# carpeta actual de la sesión (sigue al worktree); si falta, la de arranque
dir=$(nested workspace current_dir)
[ -z "$dir" ] && dir=$(val project_dir)
[ -z "$dir" ] && dir=$(pwd)
project=$(basename "$dir")

# rama y estado de git solo dentro de un worktree (git worktree add o sesión en worktree)
git_worktree=$(nested workspace git_worktree)
wt_branch=$(nested worktree branch)
vcs=""; vcs_bg=2
if [ -n "$git_worktree" ] || [ -n "$(nested worktree path)" ]; then
  git_status=$(git --no-optional-locks -C "$dir" status --porcelain=v2 --branch 2>/dev/null)
  branch=$(echo "$git_status" | sed -n 's/^# branch.head //p')
  [ -z "$branch" ] || [ "$branch" = "(detached)" ] && branch="${wt_branch:-$branch}"
  if [ -n "$branch" ]; then
    ahead=$(echo "$git_status" | sed -n 's/^# branch.ab +\([0-9]*\) -[0-9]*$/\1/p')
    behind=$(echo "$git_status" | sed -n 's/^# branch.ab +[0-9]* -\([0-9]*\)$/\1/p')
    staged=$(echo "$git_status" | grep -cE '^[12] [^.]')
    unstaged=$(echo "$git_status" | grep -cE '^[12] .[^.]')
    conflicts=$(echo "$git_status" | grep -c '^u ')
    untracked=$(echo "$git_status" | grep -c '^? ')
    # mismos símbolos que el segmento vcs de p10k
    vcs=" ${branch}"
    [ "${behind:-0}" -gt 0 ] && vcs="${vcs} ⇣${behind}"
    [ "${ahead:-0}" -gt 0 ] && vcs="${vcs} ⇡${ahead}"
    [ "$conflicts" -gt 0 ] && vcs="${vcs} ~${conflicts}"
    [ "$staged" -gt 0 ] && vcs="${vcs} +${staged}"
    [ "$unstaged" -gt 0 ] && vcs="${vcs} !${unstaged}"
    [ "$untracked" -gt 0 ] && vcs="${vcs} ?${untracked}"
    # verde si está limpio, amarillo si hay cambios (VCS_CLEAN/MODIFIED_BACKGROUND)
    [ $((staged + unstaged + conflicts)) -gt 0 ] && vcs_bg=3
  fi
fi
model=$(val display_name)
model_raw="$model"
model="${model% (*context)}"
model="${model% (*tokens)}"
case "$model_raw" in *1M*|*1m*) model="${model} - 1M";; esac
ctx_pct=$(round "$(nested2 context_window used_percentage)")

# datos de la sesión: costo estimado, duración y líneas cambiadas
cost_usd=$(nested cost total_cost_usd)
duration_ms=$(nested cost total_duration_ms)
lines_added=$(nested cost total_lines_added)
lines_removed=$(nested cost total_lines_removed)

# modo rápido (/fast) y caché de prompts
fast_mode=$(val fast_mode)
cache_ratio=$(nested2 prompt_cache hit_ratio)
cache_warm=$(nested2 prompt_cache warm)

# recordatorio de /rename: el nombre puesto a mano queda en el transcript como "custom-title";
# mientras no exista, se muestra la pill
transcript=$(val transcript_path)
rename_hint=""
if [ -n "$transcript" ] && ! grep -q '"type":"custom-title"' "$transcript" 2>/dev/null; then
  rename_hint="/rename"
fi

# duración legible: 45s, 23m, 1h 23m
format_duration() {
  local s=$(( ${1%.*} / 1000 ))
  if [ "$s" -ge 3600 ]; then printf "%dh %02dm" $((s / 3600)) $(( (s % 3600) / 60 ))
  elif [ "$s" -ge 60 ]; then printf "%dm" $((s / 60))
  else printf "%ds" "$s"
  fi
}

# nivel de razonamiento (/effort), con mayúscula inicial: Low, Medium, High, XHigh, Max
effort=$(nested effort level)
case "$effort" in
  xhigh) effort="XHigh" ;;
  "")    ;;
  *)     effort="$(echo "${effort:0:1}" | tr '[:lower:]' '[:upper:]')${effort:1}" ;;
esac

session_pct=$(round "$(nested five_hour used_percentage)")
session_reset=$(nested five_hour resets_at)
week_pct=$(round "$(nested seven_day used_percentage)")
week_reset=$(nested seven_day resets_at)

time_left() {
  local reset=$1 now
  now=$(date +%s)
  [ -z "$reset" ] && return
  [ "$reset" -le "$now" ] 2>/dev/null && return
  local diff=$((reset - now))
  local days=$((diff / 86400))
  local hours=$(( (diff % 86400) / 3600 ))
  local mins=$(( (diff % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    printf "%dd %02dh" "$days" "$hours"
  else
    printf "%02d:%02d" "$hours" "$mins"
  fi
}

session_time=$(time_left "$session_reset")
week_time=$(time_left "$week_reset")

make_bar() {
  local pct=${1:-0} width=${2:-8}
  local filled_8ths=$(awk -v p="$pct" -v w="$width" 'BEGIN{ v=int((p/100)*w*8+0.5); if(v>w*8)v=w*8; if(v<0)v=0; print v }')
  local full=$((filled_8ths / 8))
  local frac=$((filled_8ths % 8))
  local bar="" i
  local parts=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉")
  for ((i=0; i<full && i<width; i++)); do bar="${bar}▒"; done
  if [ "$full" -lt "$width" ] && [ "$frac" -gt 0 ]; then
    bar="${bar}▒"
    full=$((full + 1))
  fi
  for ((i=full; i<width; i++)); do bar="${bar}░"; done
  echo "$bar"
}

# Estilo Powerlevel10k (ver ~/.p10k.zsh): puntas redondeadas, segmentos pegados, paleta de 256 colores
R="\033[0m"
bgc() { printf '\033[48;5;%sm' "$1"; }
fgc() { printf '\033[38;5;%sm' "$1"; }

# color de fondo según el % de uso: verde, amarillo o rojo (como vcs/status en p10k)
level_bg() {
  local p=${1:-0}
  if [ "$p" -ge 80 ] 2>/dev/null; then echo 1
  elif [ "$p" -ge 60 ] 2>/dev/null; then echo 3
  else echo 2
  fi
}

seg_bg=(); seg_fg=(); seg_txt=()
seg() { seg_bg+=("$1"); seg_fg+=("$2"); seg_txt+=("$3"); }

# ancho visible en caracteres (los iconos Nerd Font Mono ocupan una celda)
export LC_ALL=en_US.UTF-8
text_width() { local t; t=$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g'); echo "${#t}"; }

# convierte los segmentos acumulados en una cadena p10k (chain, chain_w) y los vacía
chain=""; chain_w=0
render_chain() {
  local count=${#seg_bg[@]} i txt
  chain=""; chain_w=0
  [ "$count" -eq 0 ] && return
  chain="$(fgc "${seg_bg[0]}")"
  chain_w=2
  for ((i=0; i<count; i++)); do
    txt=" ${seg_txt[i]} "
    chain="${chain}$(bgc "${seg_bg[i]}")$(fgc "${seg_fg[i]}")${txt}"
    chain_w=$((chain_w + $(text_width "$txt")))
    if [ $((i + 1)) -lt "$count" ]; then
      if [ "${seg_bg[i+1]}" = "${seg_bg[i]}" ]; then
        chain="${chain}$(fgc "${seg_fg[i]}")"
      else
        chain="${chain}$(bgc "${seg_bg[i+1]}")$(fgc "${seg_bg[i]}")"
      fi
      chain_w=$((chain_w + 1))
    fi
  done
  chain="${chain}${R}$(fgc "${seg_bg[count-1]}")${R}"
  seg_bg=(); seg_fg=(); seg_txt=()
}

# segmento con barra: "Nombre ▒░░░░░░░ N%" y tiempo hasta el reset con el reloj de arena de p10k
bar_seg() {
  local pct="$1" name="$2" time="$3" width="$4"
  local bar; bar=$(make_bar "$pct" "$width")
  local clock=""; [ -n "$time" ] && clock="  ${time}"
  seg "$(level_bg "$pct")" 0 "${name} ${bar} ${pct}%${clock}"
}

# ancho de la terminal (Claude Code lo pasa en COLUMNS). Claude Code sangra el statusline y recorta con … lo que
# pasa de COLUMNS - 4, así que ese es el ancho útil; sin COLUMNS no se reparte
term_w=0; [ "${COLUMNS:-0}" -gt 4 ] && term_w=$((COLUMNS - 4))

# píldora de líneas
lines_txt=""
if [ -n "$lines_added" ] || [ -n "$lines_removed" ]; then
  # barra de diff con los números dentro: un tramo verde con +N y uno rojo con −N, de largo proporcional
  # a las líneas añadidas y quitadas (mínimo lo que ocupa cada número); 10 celdas o más si no caben
  la=${lines_added:-0}; lr=${lines_removed:-0}
  add_txt="+${la}"; del_txt="−${lr}"
  add_len=${#add_txt}; del_len=$(text_width "$del_txt")
  bar_w=10; [ $((add_len + del_len + 2)) -gt "$bar_w" ] && bar_w=$((add_len + del_len + 2))
  if [ $((la + lr)) -gt 0 ]; then
    green=$(( (la * bar_w * 2 + (la + lr)) / ((la + lr) * 2) ))
  else
    green=$((bar_w / 2))
  fi
  [ "$green" -lt $((add_len + 1)) ] && green=$((add_len + 1))
  [ $((bar_w - green)) -lt $((del_len + 1)) ] && green=$((bar_w - del_len - 1))
  red=$((bar_w - green))
  # texto centrado en cada tramo; sin cambios, los dos tramos en gris
  center() { local t="$1" w="$2" l; l=$(text_width "$t"); local p=$((w - l)); printf '%*s%s%*s' $((p / 2)) '' "$t" $((p - p / 2)) ''; }
  add_bg=28; del_bg=124; [ $((la + lr)) -eq 0 ] && add_bg=240 && del_bg=240
  diff_bar="$(bgc "$add_bg")$(fgc 254)$(center "$add_txt" "$green")$(bgc "$del_bg")$(center "$del_txt" "$red")$(bgc 238)$(fgc 254)"
  # archivos con cambios en el repo (git status, incluye los sin seguimiento)
  files=$(git --no-optional-locks -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  files_txt=""
  if [ "${files:-0}" -gt 0 ]; then
    files_txt="${files} "
  fi
  lines_txt="Lines ${diff_bar}"
fi
# ancho de la píldora: puntas, márgenes y, si hay archivos, el separador y el segundo tramo
lines_w=0
if [ -n "$lines_txt" ]; then
  lines_w=$((4 + $(text_width "$lines_txt") + 4))   # + el tramo del icono (separador, icono y márgenes)
  [ -n "$files_txt" ] && lines_w=$((lines_w + 3 + $(text_width "$files_txt")))
fi

# línea 2: cada uso va en su propia píldora. Se guardan aparte para repartirlas al final: si una no cabe en el
# ancho de la terminal pasa a la fila siguiente (como el wrap de p10k), y los espacios entre ellas se estiran
# para igualar el ancho de la línea 1
pill_chain=(); pill_w=(); pill_row=(); rows=0; row_w=0; line2_w=0
add_pill() {
  render_chain
  [ -z "$chain" ] && return
  if [ "$row_w" -gt 0 ] && [ "$term_w" -gt 0 ] && [ $((row_w + 2 + chain_w)) -gt "$term_w" ]; then
    rows=$((rows + 1)); row_w=0
  fi
  [ "$row_w" -gt 0 ] && row_w=$((row_w + 2))
  row_w=$((row_w + chain_w))
  pill_chain+=("$chain"); pill_w+=("$chain_w"); pill_row+=("$rows")
  [ "$row_w" -gt "$line2_w" ] && line2_w=$row_w
}
[ -n "$ctx_pct" ]     && bar_seg "$ctx_pct" "Context" && add_pill
[ -n "$session_pct" ] && bar_seg "$session_pct" "Today" "$session_time" && add_pill
today_w=0; [ -n "$session_pct" ] && today_w=${pill_w[${#pill_w[@]}-1]}
[ -n "$week_pct" ]    && bar_seg "$week_pct" "Week" "$week_time" && add_pill

# línea 3: la sesión actual, en tonos neutros para no confundirse con los límites
new_row() { [ "${#pill_chain[@]}" -gt 0 ] && [ "$row_w" -gt 0 ] && rows=$((rows + 1)); row_w=0; }
line3_row=-1
if [ -n "$cost_usd" ] || [ -n "$duration_ms" ] || [ -n "$lines_added" ] || [ -n "$lines_removed" ] || [ -n "$cache_warm" ]; then
  new_row
  line3_row=$rows
  # duración: icono en azul petróleo y valor en un azul más claro
  if [ -n "$duration_ms" ]; then
    seg 24 254 "󰔛"
    seg 31 254 "Time $(format_duration "$duration_ms")"
    add_pill
  fi
  if [ -n "$lines_txt" ]; then
    # mismo ancho que la píldora de Today (encima, en la misma columna): se rellena con espacios a ambos lados
    pad=$((today_w - lines_w))
    [ "$pad" -gt 0 ] && lines_txt="$(printf '%*s' $((pad / 2)) '')${lines_txt}$(printf '%*s' $((pad - pad / 2)) '')"
    # tres tonos de gris, del más oscuro al más claro: icono, líneas y archivos (como manzana, Time o Cost)
    seg 236 254 ""
    seg 238 254 "$lines_txt"
    [ -n "$files_txt" ] && seg 250 232 "$files_txt"
    add_pill
  fi
  # costo y caché en una sola píldora (la caché es lo que abarata el costo): icono y valor del costo en
  # ciruela oscuro y claro; la caché en verde azulado si sigue activa o gris con copo de nieve si se enfrió
  if [ -n "$cost_usd" ] || [ -n "$cache_warm" ]; then
    if [ -n "$cost_usd" ]; then
      seg 53 254 "󰖄"
      seg 90 254 "Cost \$$(printf '%.2f' "$cost_usd")"
    fi
    if [ -n "$cache_warm" ]; then
      cache_pct="—"; [ -n "$cache_ratio" ] && [ "$cache_ratio" != "null" ] && cache_pct="$(awk -v r="$cache_ratio" 'BEGIN{printf "%.0f", r*100}')%"
      if [ "$cache_warm" = "true" ]; then
        seg 29 254 "󰆼 Cache ${cache_pct}"
      else
        seg 240 254 "󰆼 Cache ${cache_pct} 󰜗"
      fi
    fi
    add_pill
  fi
fi

# PR abierto de la rama (pr.number, pr.review_state); en GitLab es un MR y se escribe !N
pr_number=$(nested pr number)
pr_state=$(nested pr review_state)
pr=""; pr_bg=4; pr_fg=254
if [ -n "$pr_number" ]; then
  pr_prefix="#"; [ "$(nested pr kind)" = "mr" ] && pr_prefix="!"
  pr=" ${pr_prefix}${pr_number}"
  # verde aprobado, amarillo claro pendiente (distinto del amarillo de la rama), rojo con cambios pedidos, gris borrador
  case "$pr_state" in
    approved)          pr="${pr} ✔"; pr_bg=2; pr_fg=0 ;;
    pending)           pr="${pr} ●"; pr_bg=222; pr_fg=0 ;;
    changes_requested) pr="${pr} ✘"; pr_bg=1; pr_fg=254 ;;
    draft)             pr="${pr} ✎"; pr_bg=8; pr_fg=254 ;;
  esac
fi

# línea 1: Apple y proyecto (os_icon + dir) ─── modelo, como el gap de p10k
seg 253 232 ""
[ -n "$project" ] && seg 4 254 " ${project}"
[ -n "$rename_hint" ] && seg 172 0 "󰏫" && seg 214 0 "$rename_hint"
[ -n "$vcs" ]     && seg "$vcs_bg" 0 "$vcs"
[ -n "$pr" ]      && seg "$pr_bg" "$pr_fg" "$pr"
render_chain
left="$chain"; left_w=$chain_w
# si la rama y el PR no caben junto al proyecto, van en su propia línea
if { [ -n "$vcs" ] || [ -n "$pr" ]; } && [ "$term_w" -gt 0 ] && [ "$left_w" -gt "$term_w" ]; then
  seg 253 232 ""
  [ -n "$project" ] && seg 4 254 " ${project}"
  [ -n "$rename_hint" ] && seg 172 0 "󰏫" && seg 214 0 "$rename_hint"
  render_chain
  left="$chain"; left_w=$chain_w
  [ -n "$vcs" ] && seg "$vcs_bg" 0 "$vcs"
  [ -n "$pr" ]  && seg "$pr_bg" "$pr_fg" "$pr"
  render_chain
  left="${left}\n${chain}"; left_w=$chain_w
fi
# color del modelo según la familia (sin chocar con el verde/amarillo/rojo del uso ni con el azul del proyecto)
model_colors() {
  case "$(echo "$model" | tr '[:upper:]' '[:lower:]')" in
    # fondo del modelo, letra y fondo del effort (un tono más claro del mismo color)
    *opus*)   echo "90 254 127" ;;   # magenta oscuro / magenta
    *sonnet*) echo "30 254 37" ;;    # verde azulado oscuro / verde azulado
    *haiku*)  echo "240 254 244" ;;  # gris pizarra / gris medio
    *fable*)  echo "130 254 172" ;;  # cobre / naranja cobrizo
    *)        echo "7 232 250" ;;    # gris claro, como os_icon / gris más claro
  esac
}
if [ -n "$model" ]; then
  read -r model_bg model_fg effort_bg <<< "$(model_colors)"
  model_txt="󰧑 ${model}"
  # rayo cuando el modo rápido está activo
  [ "$fast_mode" = "true" ] && model_txt="${model_txt} 󱐋"
  seg "$model_bg" "$model_fg" "$model_txt"
  # effort pegado al modelo, en un tono más claro del mismo color
  [ -n "$effort" ] && seg "$effort_bg" "$model_fg" "󰓅 ${effort}"
fi
render_chain
right="$chain"; right_w=$chain_w

# ancho común: con COLUMNS, todo el ancho de la terminal, como p10k (la línea ─ llega al borde derecho y las
# píldoras de abajo se reparten a lo ancho). Sin COLUMNS, el mayor entre la línea 1 (con un ─ como mínimo) y la
# fila más ancha de abajo
if [ "$term_w" -gt 0 ]; then
  target=$term_w
else
  target=$line2_w
  case "$left" in *"\n"*) ;; *) [ $((left_w + 1 + right_w)) -gt "$target" ] && target=$((left_w + 1 + right_w)) ;; esac
fi
gap_w=$((target - left_w - right_w))
[ "$gap_w" -lt 1 ] && gap_w=1
# si el modelo no cabe al lado del proyecto, baja a su propia línea
if [ "$term_w" -gt 0 ] && [ -n "$right" ] && [ $((left_w + gap_w + right_w)) -gt "$term_w" ]; then
  right="\n${right}"; gap_w=0
fi
gap=""; for ((i=0; i<gap_w; i++)); do gap="${gap}─"; done

# arma cada fila de abajo alineada en columnas: la primera píldora a la izquierda, la última pegada a la
# derecha y las del medio centradas en su fracción del ancho (con 3, en el centro). Así las filas con el mismo
# número de píldoras quedan alineadas. Si no caben así, se reparten con separaciones iguales
line2=""
for ((r=0; r<=rows; r++)); do
  idx=(); w=0
  for ((i=0; i<${#pill_chain[@]}; i++)); do
    [ "${pill_row[i]}" -eq "$r" ] || continue
    idx+=("$i"); w=$((w + pill_w[i]))
  done
  n=${#idx[@]}
  [ "$n" -eq 0 ] && continue
  # posición de inicio de cada píldora
  starts=(); ok=1; prev_end=0
  for ((k=0; k<n; k++)); do
    pw=${pill_w[idx[k]]}
    if [ "$k" -eq 0 ]; then st=0
    elif [ "$k" -eq $((n - 1)) ]; then st=$((target - pw))
    else st=$(( (k * target) / (n - 1) - pw / 2 ))
    fi
    [ "$k" -gt 0 ] && [ "$st" -lt $((prev_end + 2)) ] && ok=0
    starts+=("$st"); prev_end=$((st + pw))
  done
  if [ "$ok" -eq 0 ] || [ "$n" -eq 1 ]; then
    # reparto con separaciones iguales (mínimo 2)
    starts=(); seps=$((n - 1)); extra=0
    [ "$seps" -gt 0 ] && extra=$((target - w - 2 * seps))
    [ "$extra" -lt 0 ] && extra=0
    pos=0
    for ((k=0; k<n; k++)); do
      if [ "$k" -gt 0 ]; then
        sp=$((2 + extra / seps)); [ $((k - 1)) -lt $((extra % seps)) ] && sp=$((sp + 1))
        pos=$((pos + sp))
      fi
      starts+=("$pos"); pos=$((pos + pill_w[idx[k]]))
    done
  fi
  row=""; prev_end=0
  for ((k=0; k<n; k++)); do
    if [ "$k" -gt 0 ]; then
      sp=$((starts[k] - prev_end))
      if [ "$line3_row" -ge 0 ] && [ "$r" -ge "$line3_row" ]; then
        # en la línea 3 las píldoras se unen con una línea ─ gris, como la de la línea 1
        dash=""; for ((d=0; d<sp; d++)); do dash="${dash}─"; done
        row="${row}$(fgc 244)${dash}${R}"
      else
        row="${row}$(printf '%*s' "$sp" '')"
      fi
    fi
    row="${row}${pill_chain[idx[k]]}"; prev_end=$((starts[k] + pill_w[idx[k]]))
  done
  [ -n "$line2" ] && line2="${line2}\n"
  line2="${line2}${row}"
done

# línea vacía arriba, como PROMPT_ADD_NEWLINE de p10k. Claude Code descarta las líneas vacías, de espacios
# o de espacio duro, así que lleva un espacio de ancho cero (U+200B)
out="​\n${left}$(fgc 244)${gap}${R}${right}"
[ -n "$line2" ] && out="${out}\n${line2}"

printf "%b" "$out"
