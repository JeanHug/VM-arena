{
  echo "===== [ACTION] 10 T/S v3 — tête MTP OFFICIELLE ggml-org ====="
  echo "# host: $(hostname) | date: $(date -u +%FT%TZ)"
  cd "$HOME/persist" || exit 1
  export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
  mkdir -p "$HOME/gguf-cache/v3"
  Q="Quelle est la capitale de la France ?"
  pip3 install -q -U huggingface_hub 2>/dev/null

  echo "--- main IQ3_S (AesSedai, 86 s via Xet) ---"
  python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(repo_id='AesSedai/Qwen3.6-35B-A3B-GGUF', allow_patterns=['IQ3_S/*.gguf'], local_dir='$HOME/gguf-cache/v3/main', max_workers=4)
print('main OK')"
  MAIN=$(find "$HOME/gguf-cache/v3/main" -name "*-00001-of-00002.gguf" | head -1)

  echo "--- tête MTP officielle (Q4_0, 1 Go) ---"
  python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='ggml-org/Qwen3.6-35B-A3B-GGUF', filename='mtp-Qwen3.6-35B-A3B-Q4_0.gguf', local_dir='$HOME/gguf-cache/v3/mtp')
print('mtp OK')"
  MTP=$(find "$HOME/gguf-cache/v3/mtp" -name "*.gguf" | head -1)

  echo ""
  echo "--- TEST A : draft-mtp avec la tête officielle ---"
  timeout 420 bin/llama-cli -m "$MAIN" -md "$MTP" --spec-type draft-mtp --spec-draft-n-max 6 \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    -st -p "$Q" -n 250 --temp 0 --threads 4 --simple-io </dev/null > /tmp/a.log 2>&1
  RC=$?
  echo "réponse : $(grep -a "Paris" /tmp/a.log | head -1 | tail -c 130)"
  grep -aE "Prompt:|Generation:" /tmp/a.log | tail -1
  grep -aiE "accept" /tmp/a.log | tail -2
  [ $RC -ne 0 ] && { echo "(MTP officiel échec code=$RC):"; tail -8 /tmp/a.log | tr '\r' '\n' | grep -avE "^\s*$" | tail -6; }

  if [ $RC -ne 0 ] || ! grep -aq "Generation:" /tmp/a.log; then
    echo ""
    echo "--- TEST B : draft-dflash avec dflash-Q8_0 officiel (421 Mo) ---"
    python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='ggml-org/Qwen3.6-35B-A3B-GGUF', filename='dflash-Qwen3.6-35B-A3B-Q8_0.gguf', local_dir='$HOME/gguf-cache/v3/df')
print('dflash OK')"
    DF=$(find "$HOME/gguf-cache/v3/df" -name "*.gguf" | head -1)
    timeout 420 bin/llama-cli -m "$MAIN" -md "$DF" --spec-type draft-dflash --spec-draft-n-max 6 \
      --cache-type-k q8_0 --cache-type-v q8_0 \
      -st -p "$Q" -n 250 --temp 0 --threads 4 --simple-io </dev/null > /tmp/b.log 2>&1
    RC2=$?
    echo "réponse : $(grep -a "Paris" /tmp/b.log | head -1 | tail -c 130)"
    grep -aE "Prompt:|Generation:" /tmp/b.log | tail -1
    grep -aiE "accept" /tmp/b.log | tail -2
    [ $RC2 -ne 0 ] && { echo "(dflash échec code=$RC2):"; tail -8 /tmp/b.log | tr '\r' '\n' | grep -avE "^\s*$" | tail -6; }
  fi

  echo ""
  rm -rf "$HOME/gguf-cache/v3" && echo "purgé ✓"
  echo "===== FIN v3 ====="
} 2>&1
exit 0
