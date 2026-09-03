{
  echo "===== [ACTION] GÉNÉRATION — chat roux forêt ensoleillée (FLUX.2-klein-4B, éphémère) ====="
  echo "# host: $(hostname) | date: $(date -u +%FT%TZ)"
  cd "$HOME/persist" || exit 1
  mkdir -p "$HOME/flux-tmp/bin" "$HOME/flux-tmp/w" "$GITHUB_WORKSPACE/bridge/artifacts"
  T0=$(date +%s)

  echo "--- 1) doc officielle flux2 de sd.cpp ---"
  curl -sL --max-time 30 "https://raw.githubusercontent.com/leejet/stable-diffusion.cpp/master/docs/flux2.md" > /tmp/flux2.md
  head -60 /tmp/flux2.md

  echo ""
  echo "--- 2) binaire sd.cpp linux-x64 (release master-841) ---"
  REL="https://github.com/leejet/stable-diffusion.cpp/releases/download/master-841-6b3edaa"
  # lister les assets pour trouver le bon nom
  curl -sL --max-time 30 "https://api.github.com/repos/leejet/stable-diffusion.cpp/releases/tags/master-841-6b3edaa" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for a in d.get('assets',[]): print('  asset:', a['name'], a.get('size',0)//1000000, 'Mo')
except Exception as e: print('err:', e)"
  ASSET=$(curl -sL --max-time 30 "https://api.github.com/repos/leejet/stable-diffusion.cpp/releases/tags/master-841-6b3edaa" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for a in d.get('assets',[]):
        n=a['name'].lower()
        if 'linux' in n and 'x64' in n and 'avx2' in n and 'cuda' not in n and 'vulkan' not in n and 'rocm' not in n: print(a['name']); break
except Exception: pass")
  if [ -z "$ASSET" ]; then
    ASSET=$(curl -sL --max-time 30 "https://api.github.com/repos/leejet/stable-diffusion.cpp/releases/tags/master-841-6b3edaa" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for a in d.get('assets',[]):
        n=a['name'].lower()
        if 'linux' in n and 'x64' in n and 'cuda' not in n and 'vulkan' not in n and 'rocm' not in n and 'opencl' not in n: print(a['name']); break
except Exception: pass")
  fi
  echo "asset retenu : $ASSET"
  [ -z "$ASSET" ] && { echo "❌ pas de binaire linux — arrêt"; exit 1; }
  curl -sL --retry 2 --max-time 300 -o /tmp/sd.zip "$REL/$ASSET"
  python3 -c "import zipfile; zipfile.ZipFile('/tmp/sd.zip').extractall('/tmp/sdx')"
  find /tmp/sdx -name 'sd*' -type f -exec cp {} "$HOME/flux-tmp/bin/" \; 2>/dev/null
  SD=$(find "$HOME/flux-tmp/bin" -name 'sd*' -type f | head -1)
  chmod +x "$SD"
  echo "binaire : $SD ($("$SD" --version 2>&1 | head -1))"

  echo ""
  echo "--- 3) fichiers GGUF klein-4B (leejet) ---"
  curl -sL --max-time 30 "https://huggingface.co/api/models/leejet/FLUX.2-klein-4B-GGUF/tree/main" | python3 -c "
import json,sys
try:
    for f in json.load(sys.stdin):
        if f['path'].endswith('.gguf'): print(f\"   {f['path']}: {f.get('size',0)//1000000} Mo\")
except Exception as e: print('err:', e)"

  echo ""
  echo "--- 4) téléchargements (diffusion + encoders indiqués par la doc) ---"
  pip3 install -q -U huggingface_hub 2>/dev/null
  # diffusion model : Q4_K_S si dispo sinon Q4_K_M sinon premier
  DIFF=$(curl -sL --max-time 30 "https://huggingface.co/api/models/leejet/FLUX.2-klein-4B-GGUF/tree/main" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    files=[(f['path'],f.get('size',0)) for f in d if f['path'].endswith('.gguf')]
    prefs=['q4_k_s','q4_k_m','q5_k_s','q4_0','q8_0']
    for p in prefs:
        for path,s in files:
            if p in path.lower() and 'mmproj' not in path.lower() and 't5' not in path.lower() and 'clip' not in path.lower() and 'text' not in path.lower() and 'vae' not in path.lower() and s>1_000_000_000:
                print(path); sys.exit()
except Exception: pass")
  echo "modèle de diffusion : $DIFF"
  python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='leejet/FLUX.2-klein-4B-GGUF', filename='$DIFF', local_dir='$HOME/flux-tmp/w')
print('diffusion OK')"
  # encoders : ceux cités dans la doc (on tente les noms mmproj/clip/t5 du même dépôt)
  for ENC in $(curl -sL --max-time 30 "https://huggingface.co/api/models/leejet/FLUX.2-klein-4B-GGUF/tree/main" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for f in d:
        p=f['path'].lower()
        if p.endswith('.gguf') and any(k in p for k in ('mmproj','clip','t5','text','qwen','mistral','llava')): print(f['path'])
except Exception: pass"); do
    echo "  encoder : $ENC"
    python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='leejet/FLUX.2-klein-4B-GGUF', filename='$ENC', local_dir='$HOME/flux-tmp/w')
print('  OK')" || echo "  !! échec $ENC"
  done
  find "$HOME/flux-tmp/w" -name "*.gguf" -exec du -h {} \;

  echo ""
  echo "--- 5) GÉNÉRATION (512x768, steps selon doc, 4 threads) ---"
  # args encoders selon la doc : on tente --llm/--t5/--clip automatiquement
  LLM=$(find "$HOME/flux-tmp/w" -iname "*qwen*" -o -iname "*mistral*" -o -iname "*t5*" -o -iname "*text*" | grep -i gguf | head -1)
  CLIP=$(find "$HOME/flux-tmp/w" -iname "*clip*" -o -iname "*mmproj*" | grep -i gguf | head -1)
  DIFFP=$(find "$HOME/flux-tmp/w" -name "*.gguf" | grep -viE "qwen|mistral|t5|text|clip|mmproj" | head -1)
  ARGS=""
  [ -n "$LLM" ] && ARGS="$ARGS --llm $LLM"
  [ -n "$CLIP" ] && ARGS="$ARGS --clip $CLIP"
  echo "diffusion : $DIFFP"
  echo "args encoders : $ARGS"
  timeout 1080 "$SD" -m "$DIFFP" $ARGS \
    -p "an orange tabby cat walking through a sunlit forest, warm golden sunlight rays filtering through green trees, photorealistic, high detail" \
    --steps 8 --cfg-anneal 0 --sampling-method euler \
    -W 512 -H 768 --threads 4 -o "$HOME/flux-tmp/chat-roux.png" 2>&1 | tail -15
  RC=$?
  echo "(code génération=$RC)"
  ls -la "$HOME/flux-tmp/"*.png 2>/dev/null

  echo ""
  echo "--- 6) publication de l'image dans le repo + purge ---"
  if [ -f "$HOME/flux-tmp/chat-roux.png" ]; then
    cp "$HOME/flux-tmp/chat-roux.png" "$GITHUB_WORKSPACE/bridge/artifacts/chat-roux-foret.png"
    echo "IMAGE PUBLIÉE dans bridge/artifacts/chat-roux-foret.png ($(du -h "$GITHUB_WORKSPACE/bridge/artifacts/chat-roux-foret.png" | cut -f1))"
  else
    echo "❌ pas d'image générée"
  fi
  rm -rf "$HOME/flux-tmp" && echo "purgé ✓ (rien de sauvegardé)"
  echo "durée totale : $(( $(date +%s) - T0 )) s"
  echo "===== FIN ====="
} 2>&1
exit 0
