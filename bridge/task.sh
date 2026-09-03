{
  echo "===== [ACTION] COURSE AUX 10 T/S — Qwen3.6-35B-A3B + MTP spéculatif ====="
  echo "# host: $(hostname) | date: $(date -u +%FT%TZ)"
  cd "$HOME/persist" || exit 1
  export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
  mkdir -p "$HOME/gguf-cache/q36mtp"
  Q="Quelle est la capitale de la France ?"

  echo "--- 1) modèle principal IQ3_S (Xet rapide) ---"
  python3 -m pip install -q -U huggingface_hub 2>/dev/null || pip3 install -q -U huggingface_hub
  python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(repo_id='AesSedai/Qwen3.6-35B-A3B-GGUF', allow_patterns=['IQ3_S/*.gguf'], local_dir='$HOME/gguf-cache/q36mtp/main', max_workers=4)
print('main OK')"
  MAIN=$(find "$HOME/gguf-cache/q36mtp/main" -name "*-00001-of-00002.gguf" | head -1)
  echo "main : $MAIN ($(du -sh $(dirname "$MAIN") | cut -f1))"

  echo "--- 2) recherche d'une tête MTP (fichier nextn/mtp ≤ 2,5 Go) ---"
  HEAD=""
  for HR in havenoammo/Qwen3.6-35B-A3B-MTP-GGUF byteshape/Qwen3.6-35B-A3B-MTP-GGUF localweights/Qwen3.6-35B-A3B-MTP-IMAT-IQ4_XS-Q8nextn-GGUF; do
    echo "dépôt : $HR"
    CAND=$(curl -sL --max-time 30 "https://huggingface.co/api/models/$HR/tree/main" | python3 -c "
import json,sys,os
try:
    d=json.load(sys.stdin)
    for f in d:
        p=f['path']
        if p.endswith('.gguf') and any(k in p.lower() for k in ('nextn','mtp','draft')) and f.get('size',0) < 2_500_000_000 and f.get('size',0) > 100_000_000:
            print(p, f.get('size',0)); break
except Exception: pass")
    if [ -n "$CAND" ]; then
      P=$(echo "$CAND" | cut -d' ' -f1); S=$(echo "$CAND" | cut -d' ' -f2)
      echo "  → tête trouvée : $P ($(( S/1000000 )) Mo)"
      python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='$HR', filename='$P', local_dir='$HOME/gguf-cache/q36mtp/head')
print('head OK')"
      HEAD=$(find "$HOME/gguf-cache/q36mtp/head" -name "*.gguf" | head -1)
      break
    else
      echo "  (rien de valide ici)"
    fi
  done

  if [ -n "$HEAD" ]; then
    echo ""
    echo "--- 3) TEST MTP SPÉCULATIF : main + tête ($HEAD) ---"
    /usr/bin/time -f "MAX_RSS_KB=%M" timeout 420 bin/llama-cli -m "$MAIN" -md "$HEAD" \
      --spec-type mtp --draft-max 6 --draft-min 2 \
      --cache-type-k q8_0 --cache-type-v q8_0 \
      -st -p "$Q" -n 220 --temp 0 --threads 4 --simple-io </dev/null > /tmp/mtp.log 2>&1
    RC=$?
    echo "réponse : $(grep -a "Paris" /tmp/mtp.log | head -1 | tail -c 130)"
    grep -aE "Prompt:|Generation:" /tmp/mtp.log | tail -1
    grep -aiE "accept" /tmp/mtp.log | tail -2
    grep "MAX_RSS" /tmp/mtp.log | tail -1
    echo "(code=$RC)"
    if ! grep -aq "Generation:" /tmp/mtp.log; then
      echo "--- diagnostic échec MTP ---"; tail -12 /tmp/mtp.log | tr '\r' '\n' | grep -avE "^\s*$" | tail -8
    fi
  else
    echo "!! aucune tête MTP trouvée"
  fi

  echo ""
  echo "--- 4) repli : spéculatif classique avec mini-draft Qwen3.5-0.8B ---"
  python3 -c "
from huggingface_hub import hf_hub_download
p=hf_hub_download(repo_id='unsloth/Qwen3.5-0.8B-GGUF', filename='Qwen3.5-0.8B-Q8_0.gguf', local_dir='$HOME/gguf-cache/q36mtp/draft')
print('draft OK', p)" 2>/dev/null
  DRAFT=$(find "$HOME/gguf-cache/q36mtp/draft" -name "*.gguf" | head -1)
  if [ -n "$DRAFT" ]; then
    /usr/bin/time -f "MAX_RSS_KB=%M" timeout 420 bin/llama-cli -m "$MAIN" -md "$DRAFT" \
      --draft-max 6 --draft-min 2 \
      --cache-type-k q8_0 --cache-type-v q8_0 \
      -st -p "$Q" -n 220 --temp 0 --threads 4 --simple-io </dev/null > /tmp/draft.log 2>&1
    RC=$?
    echo "réponse : $(grep -a "Paris" /tmp/draft.log | head -1 | tail -c 130)"
    grep -aE "Prompt:|Generation:" /tmp/draft.log | tail -1
    grep -aiE "accept" /tmp/draft.log | tail -2
    echo "(code=$RC)"
    if ! grep -aq "Generation:" /tmp/draft.log; then
      echo "--- diagnostic échec draft ---"; tail -10 /tmp/draft.log | tr '\r' '\n' | grep -avE "^\s*$" | tail -6
    fi
  fi

  echo ""
  echo "--- 5) PURGE ---"
  rm -rf "$HOME/gguf-cache/q36mtp" && echo "purgé ✓ (rien de sauvegardé)"
  echo "===== FIN COURSE AUX 10 T/S ====="
} 2>&1
exit 0
