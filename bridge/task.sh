{
  echo "===== [ACTION] 10 T/S — v2 : tête ggml-org/nextn + repli REAP ====="
  echo "# host: $(hostname) | date: $(date -u +%FT%TZ)"
  cd "$HOME/persist" || exit 1
  export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
  mkdir -p "$HOME/gguf-cache/mtp2"
  Q="Quelle est la capitale de la France ?"
  pip3 install -q -U huggingface_hub 2>/dev/null

  echo "--- 1) le dépôt ggml-org existe-t-il pour 3.6-35B-A3B ? ---"
  MAIN=""; HEAD=""
  for R in ggml-org/Qwen3.6-35B-A3B-GGUF ggml-org/Qwen3.6-35B-A3B-it-GGUF; do
    LIST=$(curl -sL --max-time 30 "https://huggingface.co/api/models/$R/tree/main")
    if echo "$LIST" | grep -q '\.gguf'; then
      echo "dépôt trouvé : $R"
      echo "$LIST" | python3 -c "
import json,sys
try:
    for f in json.load(sys.stdin): print('   ', f['path'], f.get('size',0)//1000000, 'Mo')
except Exception: pass" | head -15
      # main : quant ≤ 13 Go (place pour la tête)
      MAINF=$(echo "$LIST" | python3 -c "
import json,sys,os
try:
    d=json.load(sys.stdin)
    cands=[(f['path'],f.get('size',0)) for f in d if f['path'].endswith('.gguf') and not f['path'].startswith('mmproj') and not f['path'].startswith('mtp') and 'nextn' not in f['path'].lower()]
    cands.sort(key=lambda x:x[1])
    for p,s in cands:
        if 9_000_000_000 < s <= 13_000_000_000: print(p); break
except Exception: pass")
      HEADF=$(echo "$LIST" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for f in d:
        p=f['path'].lower()
        if f['path'].endswith('.gguf') and ('mtp' in p or 'nextn' in p): print(f['path']); break
except Exception: pass")
      if [ -n "$MAINF" ]; then
        RSEL="$R"
        python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='$R', filename='$MAINF', local_dir='$HOME/gguf-cache/mtp2/main')
print('main OK')"
        MAIN=$(find "$HOME/gguf-cache/mtp2/main" -name "*.gguf" | head -1)
        [ -n "$HEADF" ] && python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='$R', filename='$HEADF', local_dir='$HOME/gguf-cache/mtp2/head')
print('head OK')" && HEAD=$(find "$HOME/gguf-cache/mtp2/head" -name "*.gguf" | head -1)
        break
      fi
    else
      echo "$R : absent"
    fi
  done
  # repli principal : AesSedai IQ3_S
  if [ -z "$MAIN" ]; then
    echo "ggml-org absent → main = AesSedai IQ3_S"
    python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(repo_id='AesSedai/Qwen3.6-35B-A3B-GGUF', allow_patterns=['IQ3_S/*.gguf'], local_dir='$HOME/gguf-cache/mtp2/main', max_workers=4)
print('main OK')"
    MAIN=$(find "$HOME/gguf-cache/mtp2/main" -name "*-00001-of-00002.gguf" | head -1)
  fi
  # repli tête : localweights Q8nextn
  if [ -z "$HEAD" ]; then
    echo "tête ggml-org absente → essai localweights Q8nextn"
    CAND=$(curl -sL --max-time 30 "https://huggingface.co/api/models/localweights/Qwen3.6-35B-A3B-MTP-IMAT-IQ4_XS-Q8nextn-GGUF/tree/main" | python3 -c "
import json,sys
try:
    for f in json.load(sys.stdin):
        p=f['path']
        if p.endswith('.gguf') and ('nextn' in p.lower() or 'mtp' in p.lower()):
            print(p, f.get('size',0)); break
except Exception: pass")
    echo "candidat : $CAND"
    if [ -n "$CAND" ]; then
      P=$(echo "$CAND" | cut -d' ' -f1)
      python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='localweights/Qwen3.6-35B-A3B-MTP-IMAT-IQ4_XS-Q8nextn-GGUF', filename='$P', local_dir='$HOME/gguf-cache/mtp2/head')
print('head OK')"
      HEAD=$(find "$HOME/gguf-cache/mtp2/head" -name "*.gguf" | head -1)
    fi
  fi
  echo "MAIN=$MAIN"
  echo "HEAD=$HEAD"

  if [ -n "$HEAD" ]; then
    echo ""
    echo "--- 2) TEST MTP (tête compatible espérée) ---"
    timeout 420 bin/llama-cli -m "$MAIN" -md "$HEAD" --spec-type draft-mtp --spec-draft-n-max 6 \
      --cache-type-k q8_0 --cache-type-v q8_0 \
      -st -p "$Q" -n 220 --temp 0 --threads 4 --simple-io </dev/null > /tmp/m2.log 2>&1
    RC=$?
    echo "réponse : $(grep -a "Paris" /tmp/m2.log | head -1 | tail -c 130)"
    grep -aE "Prompt:|Generation:" /tmp/m2.log | tail -1
    grep -aiE "accept" /tmp/m2.log | tail -2
    [ $RC -ne 0 ] && { echo "ECHEC MTP (code $RC):"; tail -8 /tmp/m2.log | tr '\r' '\n' | grep -avE "^\s*$" | tail -6; }
  fi

  echo ""
  echo "--- 3) repli définitif : Qwen3.6-28B-REAP20-A3B (experts élagués) ---"
  RR="barozp/Qwen3.6-28B-REAP20-A3B-GGUF"
  RF=$(curl -sL --max-time 30 "https://huggingface.co/api/models/$RR/tree/main" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    cands=[(f['path'],f.get('size',0)) for f in d if f['path'].endswith('.gguf') and not f['path'].startswith('mmproj')]
    cands.sort(key=lambda x:x[1])
    for p,s in cands:
        if 9_000_000_000 < s <= 14_000_000_000: print(p); break
except Exception: pass")
  echo "fichier REAP : $RF"
  if [ -n "$RF" ]; then
    python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='$RR', filename='$RF', local_dir='$HOME/gguf-cache/mtp2/reap')
print('reap OK')"
    REAP=$(find "$HOME/gguf-cache/mtp2/reap" -name "*.gguf" | head -1)
    timeout 360 bin/llama-cli -m "$REAP" --cache-type-k q8_0 --cache-type-v q8_0 \
      -st -p "$Q" -n 220 --temp 0 --threads 4 --simple-io </dev/null > /tmp/reap.log 2>&1
    echo "réponse : $(grep -a "Paris" /tmp/reap.log | head -1 | tail -c 130)"
    grep -aE "Prompt:|Generation:" /tmp/reap.log | tail -1
  fi

  echo ""
  rm -rf "$HOME/gguf-cache/mtp2" && echo "purgé ✓"
  echo "===== FIN v2 ====="
} 2>&1
exit 0
