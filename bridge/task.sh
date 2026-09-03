{
  echo "===== [ACTION] 10 T/S v4 — le sweet spot REAP (meilleure quant ≤ 13,5 Go) ====="
  echo "# host: $(hostname) | date: $(date -u +%FT%TZ)"
  cd "$HOME/persist" || exit 1
  export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
  mkdir -p "$HOME/gguf-cache/reap"
  Q="Quelle est la capitale de la France ?"
  pip3 install -q -U huggingface_hub 2>/dev/null

  for RR in barozp/Qwen3.6-28B-REAP20-A3B-GGUF crucible-labs/Qwen3.6-35B-A3B-REAP-48-v2-GGUF; do
    echo "### échelle de $RR :"
    curl -sL --max-time 30 "https://huggingface.co/api/models/$RR/tree/main" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for f in sorted(d, key=lambda x:x.get('size',0)):
        if f['path'].endswith('.gguf') and not f['path'].startswith('mmproj'):
            print(f\"    {f['path']}: {f.get('size',0)//1000000000} Go\")
except Exception: pass"
  done

  pick_and_run() {
    RR="$1"; P="$2"
    echo ""
    echo "### TEST : $RR → $P"
    python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='$RR', filename='$P', local_dir='$HOME/gguf-cache/reap/$(basename $RR)')
print('DL OK')" || { echo "!! DL échec"; return; }
    M=$(find "$HOME/gguf-cache/reap/$(basename $RR)" -name "*.gguf" | head -1)
    timeout 360 bin/llama-cli -m "$M" --cache-type-k q8_0 --cache-type-v q8_0 \
      -st -p "$Q" -n 250 --temp 0 --threads 4 --simple-io </dev/null > /tmp/r.log 2>&1
    echo "réponse : $(grep -a "Paris" /tmp/r.log | head -1 | tail -c 130)"
    grep -aE "Prompt:|Generation:" /tmp/r.log | tail -1
    grep "MAX_RSS\|rss" /tmp/r.log | tail -1
  }

  # barozp : la plus haute quant ≤ 13,5 Go (sens décroissant de bits)
  BP=$(curl -sL --max-time 30 "https://huggingface.co/api/models/barozp/Qwen3.6-28B-REAP20-A3B-GGUF/tree/main" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    cands=[(f['path'],f.get('size',0)) for f in d if f['path'].endswith('.gguf') and not f['path'].startswith('mmproj') and f.get('size',0)<=13_500_000_000]
    cands.sort(key=lambda x:-x[1])
    print(cands[0][0] if cands else '')
except Exception: pass")
  [ -n "$BP" ] && pick_and_run "barozp/Qwen3.6-28B-REAP20-A3B-GGUF" "$BP"

  # crucible : idem
  CR=$(curl -sL --max-time 30 "https://huggingface.co/api/models/crucible-labs/Qwen3.6-35B-A3B-REAP-48-v2-GGUF/tree/main" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    cands=[(f['path'],f.get('size',0)) for f in d if f['path'].endswith('.gguf') and not f['path'].startswith('mmproj') and f.get('size',0)<=13_500_000_000]
    cands.sort(key=lambda x:-x[1])
    print(cands[0][0] if cands else '')
except Exception: pass")
  [ -n "$CR" ] && pick_and_run "crucible-labs/Qwen3.6-35B-A3B-REAP-48-v2-GGUF" "$CR"

  echo ""
  rm -rf "$HOME/gguf-cache/reap" && echo "purgé ✓"
  echo "===== FIN v4 ====="
} 2>&1
exit 0
