{
  echo "===== [CODESPACE] INSTALLATION DEFINITIVE GEMMA 4 E2B ====="
  echo "# host: $(hostname) | date: $(date -u +%FT%TZ)"
  mkdir -p ~/bin ~/models
  export LD_LIBRARY_PATH="$HOME/bin:${LD_LIBRARY_PATH:-}"
  if ~/bin/llama-cli --version >/dev/null 2>&1; then
    echo "[MOTEUR] deja present : $(~/bin/llama-cli --version 2>&1 | head -1)"
  else
    echo "[MOTEUR] telechargement llama.cpp (build nocturne ubuntu)..."
    TAG=$(curl -sL --max-time 30 "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=1" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "[MOTEUR] build : $TAG"
    curl -sL --retry 2 --max-time 240 -o /tmp/llama.tar.gz "https://github.com/ggml-org/llama.cpp/releases/download/$TAG/llama-$TAG-bin-ubuntu-x64.tar.gz"
    rm -rf /tmp/llamacpp; mkdir -p /tmp/llamacpp
    tar -xzf /tmp/llama.tar.gz -C /tmp/llamacpp
    find /tmp/llamacpp \( -type f -o -type l \) \( -name 'llama-cli' -o -name 'lib*.so*' \) -exec cp -a {} ~/bin/ \;
    chmod +x ~/bin/llama-cli
    echo "[MOTEUR] installe : $(~/bin/llama-cli --version 2>&1 | head -1)"
  fi
  M="$HOME/models/gemma-4-E2B-it-Q4_K_M.gguf"
  if [ -s "$M" ]; then
    echo "[POIDS] deja presents : $(du -h "$M" | cut -f1)"
  else
    echo "[POIDS] telechargement gemma-4-E2B-it Q4_K_M (~2,9 Go)..."
    T1=$(date +%s)
    curl -sL --retry 3 --max-time 900 --speed-limit 20000 --speed-time 60 -o "$M" \
      "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf"
    T2=$(date +%s)
    echo "[POIDS] $(du -h "$M" | cut -f1) telecharges en $((T2-T1)) s"
  fi
  echo ""
  echo "===== TEST : Quelle est la capitale de la France ? ====="
  timeout 240 ~/bin/llama-cli -m "$M" -st -p "Quelle est la capitale de la France ?" -n 180 --temp 0 --threads 4 --simple-io </dev/null 2>&1 | grep -avE "^> |estimate|tasks|device|system_info|print_info|load:|llama_|^[[:space:]]*$" | tail -22
  echo ""
  echo "--- disque du codespace (persistance definitive) ---"
  df -h / | tail -1
  echo "bin     : $(du -sh ~/bin | cut -f1)"
  echo "models  : $(du -sh ~/models | cut -f1)"
  echo "===== INSTALLATION DEFINITIVE TERMINEE ====="
} 2>&1
exit 0
