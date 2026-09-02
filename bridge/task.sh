Q="Quelle est la capitale de la France ?"
echo "===== [ACTION] TEST BIG MODEL : Gemma-4-12B Q4_K_M (7,4 Go, dense) ====="
echo "# host: $(hostname) | RAM totale: $(free -h | awk '/Mem:/{print $2}')"
cd "$HOME/persist" || exit 1
export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
if ! bin/llama-cli --version >/dev/null 2>&1; then echo "ERREUR moteur absent"; exit 1; fi
echo "moteur : $(bin/llama-cli --version 2>&1 | head -1)"
REPO="unsloth/gemma-4-12B-it-GGUF"
PREFS="Q4_K_M|Q4_K_S"
FILE=$(curl -sL --max-time 30 "https://huggingface.co/api/models/$REPO" | PREFS="$PREFS" python3 -c "
import json,sys,os
try:
    d=json.load(sys.stdin)
    files=[s['rfilename'] for s in d.get('siblings',[]) if s['rfilename'].endswith('.gguf')]
    prefs=os.environ.get('PREFS','').split('|')
    for p in prefs:
        for f in files:
            if p in f:
                print(f); sys.exit()
    print(files[0] if files else '')
except Exception:
    pass")
[ -z "$FILE" ] && { echo "ERREUR: aucun gguf trouve"; exit 1; }
echo "fichier retenu : $FILE"
GGUF="$HOME/gguf-cache/$FILE"
mkdir -p "$HOME/gguf-cache"
if [ -s "$GGUF" ]; then
  echo "deja en cache (sans re-telechargement)"
else
  echo "telechargement (chargement TEMPORAIRE, non sauvegarde)..."
  T1=$(date +%s)
  curl -sL --retry 2 --max-time 900 --speed-limit 20000 --speed-time 60 -o "$GGUF" "https://huggingface.co/$REPO/resolve/main/$FILE"
  T2=$(date +%s)
  echo "telecharge : $(du -h "$GGUF" | cut -f1) en $((T2-T1)) s"
fi
echo "--- RAM avant inference ---"
free -h | head -2
echo ""
echo "===== QUESTION : $Q ====="
if [ -x /usr/bin/time ]; then
  /usr/bin/time -f "MAX_RSS_KB=%M" timeout 700 bin/llama-cli -m "$GGUF" -st -p "$Q" -n 220 --temp 0 --threads 4 --simple-io </dev/null > /tmp/o.log 2>&1
else
  timeout 700 bin/llama-cli -m "$GGUF" -st -p "$Q" -n 220 --temp 0 --threads 4 --simple-io </dev/null > /tmp/o.log 2>&1
fi
RC=$?
echo "--- reponse du modele ---"
grep -avE "^> |estimate|tasks|device|system_info|print_info|load:|llama_|prompt cache|^[[:space:]]*$" /tmp/o.log | tail -30
echo ""
echo "--- performances ---"
grep -E "Prompt:|Generation:" /tmp/o.log | tail -2
grep "MAX_RSS" /tmp/o.log | tail -1 | awk '{printf "RAM max du modele : %.1f Go\n", $2/1048576}'
GEN=$(grep -oP 'Generation: \K[0-9.]+' /tmp/o.log | head -1)
if [ -n "$GEN" ]; then
  awk -v g="$GEN" 'BEGIN{ if (g+0>10.0) printf "VERDICT: ⚡ %.1f t/s > 10 — SEUIL ATTEINT, chargement temporaire valide, rien n est sauvegarde\n", g; else printf "VERDICT: 🐢 %.1f t/s <= 10 — sous le seuil\n", g }'
fi
rm -f "$GGUF"
echo "(cache purge — modele non sauvegarde, code=$RC)"
exit 0
