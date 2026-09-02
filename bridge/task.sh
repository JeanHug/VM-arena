{
  echo "===== [CODESPACE] SETUP NOEUD RPC (build b10760 calé sur le pilote) ====="
  echo "# host: $(hostname) | date: $(date -u +%FT%TZ)"
  mkdir -p ~/rpcbin
  if ! ls ~/rpcbin/*rpc-server* >/dev/null 2>&1; then
    echo "téléchargement llama.cpp b10760 (exactement le build du pilote)…"
    curl -sL --retry 2 --max-time 300 -o /tmp/l.tar.gz "https://github.com/ggml-org/llama.cpp/releases/download/b10760/llama-b10760-bin-ubuntu-x64.tar.gz"
    rm -rf /tmp/lx && mkdir -p /tmp/lx && tar -xzf /tmp/l.tar.gz -C /tmp/lx
    find /tmp/lx \( -type f -o -type l \) \( -name '*rpc-server*' -o -name 'lib*.so*' \) -exec cp -a {} ~/rpcbin/ \;
  fi
  ls ~/rpcbin | head -6
  pkill -f rpc-server 2>/dev/null; sleep 1
  RPCBIN=$(find ~/rpcbin -name '*rpc-server*' | head -1)
  [ -z "$RPCBIN" ] && { echo "ERREUR: pas de rpc-server dans le tarball"; ls ~/rpcbin; exit 1; }
  echo "binaire rpc : $RPCBIN"
  export LD_LIBRARY_PATH="$HOME/rpcbin:${LD_LIBRARY_PATH:-}"
  nohup "$RPCBIN" --port 50052 > /tmp/rpc.log 2>&1 &
  sleep 4
  echo "--- processus ---"; pgrep -af rpc-server | head -2
  echo "--- port 50052 ---"
  (ss -tln 2>/dev/null || netstat -tln 2>/dev/null) | grep 50052 || { echo "(pas vu en écoute — log rpc:)"; tail -5 /tmp/rpc.log; }
  echo "--- RAM libre pour les couches du modèle ---"
  free -h | head -2
  echo "===== NOEUD RPC PRÊT — il doit rester allumé pour le test fédéré ====="
} 2>&1
exit 0
