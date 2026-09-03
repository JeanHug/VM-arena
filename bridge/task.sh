{
  echo "===== [ACTION] TEST TEMPORAIRE — QWEN 3.6 (MoE A3B) ====="
  echo "# host: $(hostname) | date: $(date -u +%FT%TZ)"
  cd "$HOME/persist" || exit 1
  export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
  mkdir -p "$HOME/gguf-cache"

  echo "--- 1) découverte des dépôts GGUF Qwen3.6 sur HuggingFace ---"
  CANDS=$(curl -sL --max-time 30 "https://huggingface.co/api/models?search=Qwen3.6&limit=100" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    ids=[m['id'] for m in d if 'gguf' in m.get('id','').lower()]
    for i in sorted(ids):
        print(i)
except Exception: pass")
  echo "$CANDS" | head -12
  REPO=$(echo "$CANDS" | grep -iE "35b.*a3b|a3b.*35b" | head -1)
  [ -z "$REPO" ] && REPO=$(echo "$CANDS" | grep -iE "a3b" | head -1)
  if [ -z "$REPO" ]; then
    echo "!! AUCUN dépôt MoE A3B trouvé en 3.6 — la génération 3.6 n'a visiblement pas de 35B-A3B"
    echo "    (référentiel 3.6 connu : 27B dense ; les -A3B appartiennent aux générations 3.5/3.8)"
    exit 0
  fi
  echo "→ dépôt retenu : $REPO"

  echo "--- 2) sélection du GGUF (3-4 bits, ≤ ~14 GiB) ---"
  FILE=$(curl -sL --max-time 30 "https://huggingface.co/api/models/$REPO" | PREFS="UD-IQ3_M|IQ3_M|UD-Q3_K_M|Q3_K_M|UD-IQ3_XXS|IQ3_XXS|UD-IQ4_XS|IQ4_XS" python3 -c "
import json,sys,os
try:
    d=json.load(sys.stdin)
    files=[f['rfilename'] for f in d.get('siblings',[]) if f['rfilename'].endswith('.gguf')]
    files=[f for f in files if not any(x in f for x in ('BF16','mmproj','-00001','-00002','F16'))]
    prefs=os.environ.get('PREFS','').split('|')
    for p in prefs:
        for f in files:
            if p in f: print(f); sys.exit()
except Exception: pass")
  [ -z "$FILE" ] && { echo "!! aucun gguf quantisé trouvé dans $REPO"; exit 0; }
  echo "fichier : $FILE"

  echo "--- 3) téléchargement TEMPORAIRE ---"
  T1=$(date +%s)
  curl -sL --retry 2 --max-time 600 -o "$HOME/gguf-cache/$FILE" "https://huggingface.co/$REPO/resolve/main/$FILE" || { echo "!! échec DL"; exit 0; }
  echo "DL : $(du -h "$HOME/gguf-cache/$FILE" | cut -f1) en $(( $(date +%s) - T1 )) s"

  echo "--- 4) vitesse (question test) ---"
  timeout 300 bin/llama-cli -m "$HOME/gguf-cache/$FILE" \
    -st -p "Quelle est la capitale de la France ?" \
    -n 150 --temp 0 --threads 4 --simple-io </dev/null > /tmp/m.log 2>&1
  echo "réponse : $(grep -a "Paris" /tmp/m.log | head -1 | tail -c 130)"
  grep -aE "Prompt:|Generation:" /tmp/m.log | tail -1
  echo ""
  echo "--- 5) PURGE (rien de sauvegardé) ---"
  rm -f "$HOME/gguf-cache/$FILE" && echo "cache purgé ✓ — codespace non concerné (tâche Actions)"
  echo "===== FIN TEST QWEN 3.6 ====="
} 2>&1
exit 0
