{
  echo "===== [CODESPACE] INSTALLATION DÉFINITIVE — QWEN3.6-35B-A3B (IQ3_S, 14 Go) ====="
  echo "# host: $(hostname) | date: $(date -u +%FT%TZ)"
  echo "--- moteur présent (persistant) ---"
  export LD_LIBRARY_PATH="$HOME/bin:${LD_LIBRARY_PATH:-}"
  ~/bin/llama-cli --version 2>&1 | head -1 || { echo "ERREUR moteur absent"; exit 1; }
  echo "--- espace disque avant ---"
  df -h / | tail -1
  FREE_KB=$(df --output=avail -k / | tail -1 | tr -d ' ')
  if [ "$FREE_KB" -lt 15728640 ]; then echo "❌ moins de 15 Go libres — installation annulée par sécurité"; exit 0; fi
  mkdir -p ~/models/qwen3.6-35b-a3b
  R="AesSedai/Qwen3.6-35B-A3B-GGUF"
  if [ -s ~/models/qwen3.6-35b-a3b/Qwen3.6-35B-A3B-IQ3_S-00002-of-00002.gguf ]; then
    echo "[POIDS] déjà présents ✓"
  else
    echo "[POIDS] installation via client HF (protocole Xet, haute vitesse)…"
    T1=$(date +%s)
    python3 -m pip install -q -U huggingface_hub 2>/dev/null || pip3 install -q -U huggingface_hub
    HF_XET_HIGH_PERFORMANCE=1 python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(repo_id='$R', allow_patterns=['IQ3_S/*.gguf'], local_dir='$HOME/models/qwen3.6-35b-a3b', max_workers=4)
print('snapshot OK')"
    RC=$?
    T2=$(date +%s)
    echo "[POIDS] terminé en $((T2-T1)) s (code $RC)"
    ls -la ~/models/qwen3.6-35b-a3b/IQ3_S/ 2>/dev/null
  fi
  MAIN=$(find ~/models/qwen3.6-35b-a3b -name "*-00001-of-00002.gguf" | head -1)
  [ -z "$MAIN" ] && { echo "❌ shard principal introuvable"; exit 1; }
  echo "modèle : $MAIN"
  echo ""
  echo "===== TEST DE VITESSE SUR LE CODESPACE ====="
  free -h | head -2
  timeout 300 ~/bin/llama-cli -m "$MAIN" \
    -st -p "Quelle est la capitale de la France ?" \
    -n 150 --temp 0 --threads 4 --simple-io </dev/null > /tmp/m.log 2>&1
  echo "réponse : $(grep -a "Paris" /tmp/m.log | head -1 | tail -c 130)"
  grep -aE "Prompt:|Generation:" /tmp/m.log | tail -1
  echo ""
  echo "--- état final du disque (le modèle RESTE) ---"
  df -h / | tail -1
  du -sh ~/models/qwen3.6-35b-a3b ~/models/gemma-4-E2B-it-Q4_K_M.gguf ~/bin 2>/dev/null
  echo "===== INSTALLATION DÉFINITIVE TERMINÉE ====="
} 2>&1
exit 0
