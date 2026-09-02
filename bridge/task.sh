Q="Quelle est la capitale de la France ?"
{
  echo "===== [FEDERE 32 Go] GEMMA-4-26B-A4B UD-Q4_K_M (16,9 Go) réparti sur 2 nœuds ====="
  echo "# host pilote: $(hostname) | date: $(date -u +%FT%TZ)"
  export GH_TOKEN="$CODESPACE_TOKEN"
  CS=$(gh api user/codespaces --jq '.codespaces[] | select(.repository.full_name=="JeanHug/VM-arena") | .name' | head -1)
  [ -z "$CS" ] && { echo "ERREUR: aucun codespace"; exit 1; }
  ST=$(gh api "user/codespaces/$CS" --jq .state)
  echo "codespace nœud distant : $CS ($ST)"
  if [ "$ST" != "Available" ]; then
    gh api -X POST "user/codespaces/$CS/start" --silent
    for i in $(seq 1 24); do sleep 10; ST=$(gh api "user/codespaces/$CS" --jq .state); [ "$ST" = "Available" ] && break; done
  fi
  [ "$ST" = "Available" ] || { echo "ERREUR: codespace pas démarré"; exit 1; }
  echo "→ Available ✓ (démarrage: $((SECONDS))s)"

  echo "--- (re)lancement du nœud rpc-server sur le codespace (via SSH) ---"
  gh codespace ssh -c "$CS" -- 'pkill -f rpc-server 2>/dev/null; export LD_LIBRARY_PATH="$HOME/rpcbin:$LD_LIBRARY_PATH"; nohup $HOME/rpcbin/ggml-rpc-server --port 50052 >/tmp/rpc.log 2>&1 & sleep 3; ss -tln | grep 50052 && echo "RPC EN ECOUTE"' 2>&1 | tail -3

  echo "--- tunnel SSH Actions→Codespace (port local 150052) ---"
  pkill -f "150052" 2>/dev/null; sleep 1
  nohup gh codespace ssh -c "$CS" -N -L 150052:127.0.0.1:50052 > /tmp/tunnel.log 2>&1 &
  TPID=$!
  sleep 8
  if ss -tln 2>/dev/null | grep -q 150052; then echo "tunnel OK ✓"; else echo "TUNNEL KO:"; tail -5 /tmp/tunnel.log; gh api -X POST "user/codespaces/$CS/stop" --silent; exit 1; fi

  cd "$HOME/persist" || exit 1
  export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
  mkdir -p "$HOME/gguf-cache"
  GGUF="$HOME/gguf-cache/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
  if [ ! -s "$GGUF" ]; then
    echo "--- téléchargement TEMPORAIRE du modèle (16,9 Go, non sauvegardé) ---"
    T1=$(date +%s)
    curl -sL --retry 2 --max-time 700 -o "$GGUF" "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
    T2=$(date +%s)
    echo "téléchargé : $(du -h "$GGUF" | cut -f1) en $((T2-T1)) s ($(( (T2-T1)/60 ))min)"
  fi
  echo "--- RAM avant (pilote) ---"; free -h | head -2
  echo ""
  echo "===== INFÉRENCE FÉDÉRÉE : couches réparties pilote+nœud (tensor-split 1,1) ====="
  echo "===== QUESTION : $Q ====="
  /usr/bin/time -f "MAX_RSS_KB=%M" timeout 780 bin/llama-cli -m "$GGUF" \
    --rpc 127.0.0.1:150052 --tensor-split 1,1 -ngl 999 \
    -st -p "$Q" -n 220 --temp 0 --threads 4 --simple-io </dev/null > /tmp/o.log 2>&1
  RC=$?
  echo "--- réponse du modèle ---"
  grep -avE "^> |estimate|tasks|system_info|print_info|load:|llama_|^[[:space:]]*$" /tmp/o.log | tail -26
  echo ""
  echo "--- lignes RPC (répartition des couches) ---"
  grep -aiE "rpc|offloaded|split" /tmp/o.log | head -8
  echo "--- performances ---"
  grep -E "Prompt:|Generation:|MAX_RSS" /tmp/o.log | tail -3
  GEN=$(grep -oP 'Generation: \K[0-9.]+' /tmp/o.log | head -1)
  [ -n "$GEN" ] && awk -v g="$GEN" 'BEGIN{ if (g+0>10.0) printf "VERDICT: ⚡ %.1f t/s > 10\n", g; else printf "VERDICT: 🐢 %.1f t/s <= 10\n", g }'
  echo ""
  echo "--- NETTOYAGE (rien de sauvegardé) ---"
  kill $TPID 2>/dev/null
  rm -f "$GGUF" && echo "cache pilote purgé ✓"
  gh codespace ssh -c "$CS" -- 'pkill -f rpc-server && echo "rpc-server tué sur le nœud ✓"' 2>&1 | tail -1
  gh api -X POST "user/codespaces/$CS/stop" --silent && echo "codespace arrêté ✓ (modèle en RAM effacé, disque intact)"
  echo "code inference=$RC — FIN DU TEST FÉDÉRÉ"
} 2>&1
exit 0
