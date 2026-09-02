Q="Quelle est la capitale de la France ?"
{
  echo "===== [FEDERE 32 Go] GEMMA-4-26B-A4B UD-Q4_K_M (16,9 Go) sur 2 nœuds ====="
  echo "# host pilote: $(hostname) | date: $(date -u +%FT%TZ)"
  export GH_TOKEN="$CODESPACE_TOKEN"
  CS=$(gh api user/codespaces --jq '.codespaces[] | select(.repository.full_name=="JeanHug/VM-arena") | .name' | head -1)
  [ -z "$CS" ] && { echo "ERREUR: aucun codespace"; exit 1; }
  ST=$(gh api "user/codespaces/$CS" --jq .state)
  echo "codespace nœud : $CS ($ST)"
  if [ "$ST" != "Available" ]; then
    gh api -X POST "user/codespaces/$CS/start" --silent
    for i in $(seq 1 24); do sleep 10; ST=$(gh api "user/codespaces/$CS" --jq .state); [ "$ST" = "Available" ] && break; done
  fi
  [ "$ST" = "Available" ] || { echo "ERREUR: codespace pas démarré"; exit 1; }

  echo "--- attente SSH du codespace (il annonce Available avant de servir) ---"
  OK=0
  for i in $(seq 1 12); do
    if gh codespace ssh -c "$CS" -- 'echo ready' >/dev/null 2>&1; then OK=1; echo "SSH prêt ($((i*10))s)"; break; fi
    sleep 10
  done
  [ "$OK" = "1" ] || { echo "ERREUR: ssh jamais prêt"; exit 1; }

  echo "--- (re)lancement du rpc-server sur le nœud ---"
  gh codespace ssh -c "$CS" -- 'pkill -f rpc-server 2>/dev/null; export LD_LIBRARY_PATH="$HOME/rpcbin:$LD_LIBRARY_PATH"; nohup $HOME/rpcbin/ggml-rpc-server --port 50052 >/tmp/rpc.log 2>&1 & sleep 3; ss -tln | grep 50052 && echo RPC_ECOUTE' 2>&1 | tail -2

  echo "--- tunnel SSH Actions→Codespace (option A: ssh-flags natifs) ---"
  pkill -f "150052" 2>/dev/null; sleep 1
  nohup gh codespace ssh -c "$CS" -- -N -L 150052:127.0.0.1:50052 </dev/null >/tmp/tunnel.log 2>&1 &
  TPID=$!
  sleep 10
  if ! ss -tln 2>/dev/null | grep -q 150052; then
    echo "option A KO — option B: config OpenSSH + ssh -L"
    gh codespace ssh --config -c "$CS" > /tmp/cs.config 2>/dev/null
    HOST_ALIAS=$(grep -i "^Host " /tmp/cs.config | head -1 | awk '{print $2}')
    echo "alias ssh: $HOST_ALIAS"
    nohup ssh -F /tmp/cs.config -o StrictHostKeyChecking=no -N -L 150052:127.0.0.1:50052 "$HOST_ALIAS" </dev/null >/tmp/tunnel2.log 2>&1 &
    TPID=$!
    sleep 10
  fi
  if ss -tln 2>/dev/null | grep -q 150052; then echo "TUNNEL OK ✓"; else echo "TUNNEL KO:"; tail -4 /tmp/tunnel.log /tmp/tunnel2.log 2>/dev/null; exit 1; fi

  cd "$HOME/persist" || exit 1
  export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
  mkdir -p "$HOME/gguf-cache"
  GGUF="$HOME/gguf-cache/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
  if [ ! -s "$GGUF" ]; then
    echo "--- téléchargement TEMPORAIRE (16,9 Go) ---"
    T1=$(date +%s)
    curl -sL --retry 2 --max-time 700 -o "$GGUF" "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
    echo "téléchargé : $(du -h "$GGUF" | cut -f1) en $(( $(date +%s) - T1 )) s"
  fi
  echo "--- RAM pilote avant ---"; free -h | head -2
  echo ""
  echo "===== INFÉRENCE FÉDÉRÉE — QUESTION : $Q ====="
  RPCFLAGS="--rpc 127.0.0.1:150052 --tensor-split 1,1"
  /usr/bin/time -f "MAX_RSS_KB=%M" timeout 720 bin/llama-cli -m "$GGUF" $RPCFLAGS -ngl 999 \
    -st -p "$Q" -n 220 --temp 0 --threads 4 --simple-io </dev/null > /tmp/o.log 2>&1
  RC=$?
  if [ $RC -ne 0 ] && grep -qiE "invalid.*split|tensor.split" /tmp/o.log; then
    echo "(split explicite refusé → nouvel essai avec répartition auto)"
    /usr/bin/time -f "MAX_RSS_KB=%M" timeout 720 bin/llama-cli -m "$GGUF" --rpc 127.0.0.1:150052 -ngl 999 \
      -st -p "$Q" -n 220 --temp 0 --threads 4 --simple-io </dev/null > /tmp/o.log 2>&1
    RC=$?
  fi
  echo "--- réponse ---"
  grep -avE "^> |estimate|tasks|system_info|print_info|load:|llama_|^[[:space:]]*$" /tmp/o.log | tail -24
  echo "--- répartition RPC ---"
  grep -aiE "rpc|offload|split" /tmp/o.log | head -8
  echo "--- performances ---"
  grep -E "Prompt:|Generation:|MAX_RSS" /tmp/o.log | tail -3
  GEN=$(grep -oP 'Generation: \K[0-9.]+' /tmp/o.log | head -1)
  [ -n "$GEN" ] && awk -v g="$GEN" 'BEGIN{ if (g+0>10.0) printf "VERDICT: ⚡ %.1f t/s > 10\n", g; else printf "VERDICT: 🐢 %.1f t/s <= 10\n", g }'
  echo ""
  echo "--- NETTOYAGE (rien de sauvegardé) ---"
  kill $TPID 2>/dev/null
  rm -f "$GGUF" && echo "cache pilote purgé ✓"
  gh codespace ssh -c "$CS" -- 'pkill -f rpc-server; echo "rpc tué ✓"' 2>&1 | tail -1
  gh api -X POST "user/codespaces/$CS/stop" --silent && echo "codespace arrêté ✓ (RAM effacée, disque intact)"
  echo "code=$RC — FIN TEST FÉDÉRÉ"
} 2>&1
exit 0
