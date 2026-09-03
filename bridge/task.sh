{
  echo "===== ÉCHELLE AA — COMPLÉMENT (2 modèles manquants) ====="
  cd "$HOME/persist" || exit 1
  export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
  mkdir -p "$HOME/gguf-cache"
  run_model() {
    NOM="$1"; shift; CANDS="$@"
    echo "## $NOM"
    FOUND=""; FILE=""
    for REPO in $CANDS; do
      FILE=$(curl -sL --max-time 25 "https://huggingface.co/api/models/$REPO" | PREFS="Q4_K_M|Q4_K_S|Q4_K_XL|UD-Q4" python3 -c "
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
      if [ -n "$FILE" ]; then FOUND="$REPO"; echo "dépôt : $REPO → $FILE"; break; else echo "dépôt $REPO : rien"; fi
    done
    [ -z "$FOUND" ] && { echo "!! aucun dépôt valide, sauté"; return; fi
    GGUF="$HOME/gguf-cache/$FILE"
    if [ ! -s "$GGUF" ]; then
      T1=$(date +%s)
      curl -sL --retry 2 --max-time 420 -o "$GGUF" "https://huggingface.co/$FOUND/resolve/main/$FILE" || { echo "!! échec DL"; rm -f "$GGUF"; return; }
      echo "DL: $(du -h "$GGUF" | cut -f1) en $(( $(date +%s) - T1 ))s"
    fi
    timeout 240 bin/llama-cli -m "$GGUF" -st -p "Quelle est la capitale de la France ?" \
      -n 150 --temp 0 --threads 4 --simple-io </dev/null > /tmp/m.log 2>&1
    echo "réponse : $(grep -a "Paris" /tmp/m.log | head -1 | tail -c 120)"
    grep -aE "Prompt:|Generation:" /tmp/m.log | tail -1
    rm -f "$GGUF"; echo "(purgé)"; echo ""
  }
  run_model "Granite-4.2-3B" "unsloth/granite-4.2-3b-GGUF" "ibm-granite/granite-4.2-3b-GGUF" "unsloth/granite-4.0-3b-GGUF" "ibm-granite/granite-4.0-3b-GGUF" "LMStudioAI/granite-4.2-3b-GGUF"
  run_model "gpt-oss-20b" "unsloth/gpt-oss-20b-GGUF" "ggml-org/gpt-oss-20b-GGUF" "openai/gpt-oss-20b-GGUF" "bartowski/gpt-oss-20b-GGUF" "NovaSky-AI/gpt-oss-20b-GGUF"
  echo "===== FIN COMPLÉMENT ====="
} 2>&1
exit 0
