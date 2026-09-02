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

  echo "--- attente SSH ---"
  OK=0
  for i in $(seq 1 12); do
    if gh codespace ssh -c "$CS" -- 'echo ready' >/dev/null 2>&1; then OK=1; echo "SSH prêt ($((i*10))s)"; break; fi
    sleep 10
  done
  [ "$OK" = "1" ] || { echo "ERREUR: ssh jamais prêt"; exit 1; }

  echo "--- tunnel (méthode C : -L + commande sleep qui maintient) ---"
  pkill -f "50552" 2>/dev/null; sleep 1
  nohup gh codespace ssh -c "$CS" -- -L 50552:127.0.0.1:50052 sleep 100000 </dev/null >/tmp/tunnel.log 2>&1 &
  TPID=$!
  TUN_OK=0
  for i in $(seq 1 6); do
    sleep 8
    if ss -tln 2>/dev/null | grep -q 50552; then TUN_OK=1; break; fi
  done
  if [ "$TUN_OK" = "1" ]; then
    echo "TUNNEL OK ✓ ($((SECONDS))s)"
  else
    echo "tunnel.log:"; cat /tmp/tunnel.log | tail -8
    echo "--- repli : ssh natif via --config ---"
    gh codespace ssh --config -c "$CS" > /tmp/cs.config 2>/dev/null
    HA=$(grep -i "^Host " /tmp/cs.config | head -1 | awk '{print $2}')
    nohup ssh -F /tmp/cs.config -o StrictHostKeyChecking=no -L 50552:127.0.0.1:50052 "$HA" sleep 100000 </dev/null >/tmp/tunnel2.log 2>&1 &
    TPID=$!
    sleep 10
    ss -tln 2>/dev/null | grep -q 50552 && { TUN_OK=1; echo "TUNNEL B OK ✓"; } || { echo "TUNNEL B KO:"; tail -5 /tmp/tunnel2.log; gh api -X POST "user/codespaces/$CS/stop" --silent; exit 1; }
  fi

  echo "--- lancement rpc-server sur le nœud (script embarqué base64) ---"
  cat > /tmp/start-rpc.sh <<'RPC'
#!/bin/bash
pkill -f "[r]pc-server" 2>/dev/null
sleep 1
export LD_LIBRARY_PATH="$HOME/rpcbin:$LD_LIBRARY_PATH"
nohup "$HOME/rpcbin/ggml-rpc-server" --port 50052 >/tmp/rpc.log 2>&1 &
sleep 3
ss -tln | grep 50052 && echo RPC_ECOUTE
exit 0
RPC
  B64=$(base64 -w0 /tmp/start-rpc.sh)
  gh codespace ssh -c "$CS" -- "echo $B64 | base64 -d > /tmp/start-rpc.sh && bash /tmp/start-rpc.sh" 2>&1 | tail -2
  echo "--- vérification indépendante (2e session SSH) ---"
  gh codespace ssh -c "$CS" -- 'ss -tln | grep 50052 && echo VU_DEPU_L_EXTERIEUR || cat /tmp/rpc.log | tail -4' 2>&1 | tail -3
  echo "--- vérif tunnel porte du trafic ---"
  timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/50552' 2>/dev/null && echo "port 50552 répond ✓" || echo "port 50552 muet ⚠️"

  cd "$HOME/persist" || exit 1
  export LD_LIBRARY_PATH="$PWD/bin:${LD_LIBRARY_PATH:-}"
  mkdir -p "$HOME/gguf-cache"
  GGUF="$HOME/gguf-cache/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
  if [ ! -s "$GGUF" ]; then
    echo "--- téléchargement TEMPORAIRE (16,9 Go) ---"
    T1=$(date +%s)
    curl -sL --retry 2 --max-time 650 -o "$GGUF" "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
    echo "téléchargé : $(du -h "$GGUF" | cut -f1) en $(( $(date +%s) - T1 )) s"
  fi
  echo "--- RAM pilote avant ---"; free -h | head -2
  echo ""
  echo "===== INFÉRENCE FÉDÉRÉE — QUESTION : $Q ====="
  echo "--- RAM du nœud distant avant chargement ---"
  gh codespace ssh -c "$CS" -- 'free -h | head -2' 2>&1 | tail -2
  echo "--- chargement fédéré -ngl 15 (19 min de budget, log temps réel) ---"
  echo "[$(date -u +%T)] début inference"
  timeout 1150 bin/llama-cli -m "$GGUF" --rpc 127.0.0.1:50552 -ngl 15 \
    -st -p "$Q" -n 100 --temp 0 --threads 4 --simple-io </dev/null > /tmp/o.log 2>&1
  RC=$?
  echo "[$(date -u +%T)] fin inference (code=$RC)"
  echo "--- où le chargement s'est arrêté (dernières lignes brutes) ---"
  tr '\r' '\n' < /tmp/o.log | grep -aE "load|rpc|Layers|CPU|RPC|buffers" | tail -12
  echo "--- réponse ---"
  grep -avE "^> |estimate|tasks|system_info|print_info|load:|llama_|^[[:space:]]*$" /tmp/o.log | tail -22
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
  gh codespace ssh -c "$CS" -- 'pkill -f "[r]pc-server"; echo "rpc tué ✓"' 2>&1 | tail -1
  gh api -X POST "user/codespaces/$CS/stop" --silent && echo "codespace arrêté ✓ (RAM effacée, disque intact)"
  echo "code=$RC — FIN TEST FÉDÉRÉ"
} 2>&1
exit 0
