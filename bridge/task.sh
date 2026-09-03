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
  echo "--- 3) téléchargement des shards (TEMPORAIRE, via client HF/xet) ---"
  T1=$(date +%s)
  pip install -q -U "huggingface_hub[hf_transfer]" 2>/dev/null || pip install -q -U huggingface_hub 2>/dev/null
  if python3 -c "import huggingface_hub" 2>/dev/null; then
    HF_HUB_ENABLE_HF_TRANSFER=1 python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(repo_id='$R', allow_patterns=['$PDIR/*.gguf'], local_dir='$HOME/gguf-cache/q36', max_workers=4)
" && echo "DL via hub OK" || echo "!! hub en échec, repli curl"
  fi
  # repli / complétion : curl avec reprise sur tout fichier manquant ou tronqué
  for FPATH in $(curl -sL --max-time 30 "https://huggingface.co/api/models/$R/tree/main/$PDIR" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for f in d:
        if f['path'].endswith('.gguf'): print(f['path'])
except Exception: pass"); do
    FN=$(basename "$FPATH")
    TGT="$HOME/gguf-cache/q36/$PDIR/$FN"
    [ -s "$TGT" ] || TGT="$HOME/gguf-cache/q36/$FN"
    if [ ! -s "$TGT" ]; then
      echo "  curl reprise : $FN"
      curl -sL -C - --retry 3 --max-time 540 -o "$TGT" "https://huggingface.co/$R/resolve/main/$FPATH"
    fi
  done
  find "$HOME/gguf-cache/q36" -name "*.gguf" -exec du -h {} \;
  echo "DL total : $(( $(date +%s) - T1 )) s"
  MAIN=$(find "$HOME/gguf-cache/q36" -name "*-00001-of-00002.gguf" | head -1)
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
