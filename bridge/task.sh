{
  echo "===== [ACTION] QWEN3.6-35B-A3B — choix de quant par taille réelle ====="
  cd "$HOME/persist" || exit 1
  export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
  mkdir -p "$HOME/gguf-cache/q36"
  R="AesSedai/Qwen3.6-35B-A3B-GGUF"
  PICK=""; PDIR=""; PSIZE=0
  for D in Q4_K_M IQ4_XS IQ3_S; do
    TOTAL=$(curl -sL --max-time 30 "https://huggingface.co/api/models/$R/tree/main/$D" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(sum(f.get('size',0) for f in d if f['path'].endswith('.gguf')))
except Exception: print(0)")
    GB=$((TOTAL/1000000000))
    echo "quant $D : ${GB} Go au total"
    if [ "$TOTAL" -gt 0 ] && [ "$TOTAL" -le 14500000000 ]; then PICK="$D"; PDIR="$D"; PSIZE=$TOTAL; fi
  done
  [ -z "$PICK" ] && { echo "!! aucune quant <= 14,5 Go (trop gros pour la VM)"; exit 0; }
  echo "→ quant retenue : $PICK ($((PSIZE/1000000000)) Go)"
  echo "--- 3) téléchargement des shards (TEMPORAIRE) ---"
  T1=$(date +%s)
  for FPATH in $(curl -sL --max-time 30 "https://huggingface.co/api/models/$R/tree/main/$PDIR" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for f in d:
        if f['path'].endswith('.gguf'): print(f['path'])
except Exception: pass"); do
    FN=$(basename "$FPATH")
    curl -sL --retry 2 --max-time 600 -o "$HOME/gguf-cache/q36/$FN" "https://huggingface.co/$R/resolve/main/$FPATH"
    echo "  $FN : $(du -h "$HOME/gguf-cache/q36/$FN" | cut -f1)"
  done
  echo "DL total : $(( $(date +%s) - T1 )) s"
  MAIN=$(ls "$HOME/gguf-cache/q36/"*-00001-of-00002.gguf | head -1)
  echo "--- 4) vitesse (question test) sur $MAIN ---"
  free -h | head -2
  timeout 300 bin/llama-cli -m "$MAIN" \
    -st -p "Quelle est la capitale de la France ?" \
    -n 150 --temp 0 --threads 4 --simple-io </dev/null > /tmp/m.log 2>&1
  echo "réponse : $(grep -a "Paris" /tmp/m.log | head -1 | tail -c 130)"
  grep -aE "Prompt:|Generation:" /tmp/m.log | tail -1
  echo ""
  echo "--- 5) PURGE ---"
  rm -rf "$HOME/gguf-cache/q36" && echo "cache purgé ✓ (rien de sauvegardé, codespace intact)"
  echo "===== FIN ====="
} 2>&1
exit 0
