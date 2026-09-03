# ============================================================
# f3-ladder.sh — ÉCHELLE DES MEILLEURS MODÈLES AA PAR TAILLE
# (prêt à exécuter dès la reconnexion GitHub)
# Chaque modèle : téléchargement TEMPORAIRE, test, purge.
# ============================================================
{
  echo "===== ÉCHELLE AA — MEILLEURS OUVERTS PAR TAILLE (Q sur capitale France) ====="
  echo "# host: $(hostname) | début: $(date -u +%FT%TZ)"
  cd "$HOME/persist" || exit 1
  export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
  mkdir -p "$HOME/gguf-cache"

  run_model() {
    NOM="$1"; REPO="$2"; PREFS="$3"; NGL="$4"
    echo ""
    echo "################################################"
    echo "## $NOM  ($REPO)"
    echo "################################################"
    FILE=$(curl -sL --max-time 25 "https://huggingface.co/api/models/$REPO" | PREFS="$PREFS" python3 -c "
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
    if [ -z "$FILE" ]; then echo "!! gguf introuvable, modèle sauté"; return; fi
    echo "fichier: $FILE"
    GGUF="$HOME/gguf-cache/$FILE"
    if [ ! -s "$GGUF" ]; then
      T1=$(date +%s)
      curl -sL --retry 2 --max-time 420 -o "$GGUF" "https://huggingface.co/$REPO/resolve/main/$FILE" || { echo "!! échec DL"; rm -f "$GGUF"; return; }
      echo "DL: $(du -h "$GGUF" | cut -f1) en $(( $(date +%s) - T1 ))s"
    fi
    timeout 240 bin/llama-cli -m "$GGUF" -st -p "Quelle est la capitale de la France ?" \
      -n 150 --temp 0 --threads 4 --simple-io </dev/null > /tmp/m.log 2>&1
    echo "réponse : $(grep -a "Paris" /tmp/m.log | head -1 | tail -c 120)"
    grep -aE "Prompt:|Generation:" /tmp/m.log | tail -1
    rm -f "$GGUF"; echo "(purgé)"
  }

  # ~3B   : Granite 4.2 3B (top "tiny" AA)          AA ≈ 10-12 | ~2 Go Q4
  run_model "Granite-4.2-3B"  "unsloth/granite-4.2-3b-GGUF"      "Q4_K_M|Q4_K_S"      99
  # ~5B   : Gemma 4 E4B (densifié efficace)         AA 12-19     | ~5 Go Q4
  run_model "Gemma-4-E4B"     "unsloth/gemma-4-E4B-it-GGUF"      "Q4_K_M|Q4_K_S"      99
  # ~9B   : Qwen 3.5 9B (meilleur 16 Go unifié)    AA ≈ 20      | ~5,6 Go Q4
  run_model "Qwen3.5-9B"      "unsloth/Qwen3.5-9B-GGUF"          "Q4_K_M|Q4_K_S"      99
  # ~20B  : gpt-oss-20b (MoE 3,6B actifs)          AA ≈ 28      | ~12,8 Go MXFP4
  run_model "gpt-oss-20b"     "unsloth/gpt-oss-20b-GGUF"         "mxfp4|MXFP4"        99
  # ~35B  : Qwen3.5-35B-A3B (MoE 3B actifs)        AA 37 ⭐     | ~12-13 Go IQ3
  run_model "Qwen3.5-35B-A3B" "unsloth/Qwen3.5-35B-A3B-GGUF"     "IQ3_XXS|IQ3_S|IQ3_XS|UD-IQ3|Q3_K_S" 99
  # (déjà mesurés séparément : E2B 15 → 15,6 t/s | 26B-A4B 31 → 4,7 t/s | Qwen3.8-27B 52 → 0,8 t/s)

  echo ""
  echo "===== FIN DE L'ÉCHELLE ($(date -u +%FT%TZ)) ====="
} 2>&1
exit 0
