{
  echo "===== [ACTION] GÉNÉRATION — chat roux forêt ensoleillée (recette officielle sd.cpp) ====="
  echo "# host: $(hostname) | début: $(date -u +%FT%TZ)"
  cd "$HOME/persist" || exit 1
  mkdir -p "$HOME/flux-tmp/bin" "$HOME/flux-tmp/w" "$GITHUB_WORKSPACE/bridge/artifacts"
  T0=$(date +%s)
  pip3 install -q -U huggingface_hub 2>/dev/null

  echo "--- 1) binaire sd.cpp (Ubuntu x86_64) ---"
  curl -sL --retry 2 --max-time 300 -o /tmp/sd.zip "https://github.com/leejet/stable-diffusion.cpp/releases/download/master-841-6b3edaa/sd-master-6b3edaa-bin-Linux-Ubuntu-24.04-x86_64.zip"
  python3 -c "import zipfile; zipfile.ZipFile('/tmp/sd.zip').extractall('/tmp/sdx')" && echo "zip OK"
  find /tmp/sdx -type f -name 'sd*' -exec cp {} "$HOME/flux-tmp/bin/" \;
  SD=$(find "$HOME/flux-tmp/bin" -type f | head -1)
  chmod +x "$SD"
  echo "binaire : $SD"
  "$SD" --version 2>&1 | head -2

  echo "--- 2) téléchargements (Xet) ---"
  # modèle de diffusion klein-4B (Q4_K_S sinon autre)
  DIFF=$(curl -sL --max-time 30 "https://huggingface.co/api/models/leejet/FLUX.2-klein-4B-GGUF/tree/main" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    files=[(f['path'],f.get('size',0)) for f in d if f['path'].endswith('.gguf')]
    for pref in ('q4_k_s','q4_k_m','q5_k_s','q4_0'):
        for p,s in files:
            if pref in p.lower(): print(p); sys.exit()
except Exception: pass")
  echo "diffusion : $DIFF"
  python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='leejet/FLUX.2-klein-4B-GGUF', filename='$DIFF', local_dir='$HOME/flux-tmp/w')
print('diffusion OK')"
  # encodeur texte : Qwen3-4B
  python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='unsloth/Qwen3-4B-GGUF', filename='Qwen3-4B-Q4_K_M.gguf', local_dir='$HOME/flux-tmp/w')
print('qwen3-4b OK')"
  # VAE flux2_ae depuis FLUX.2-dev
  VAEP=$(curl -sL --max-time 30 "https://huggingface.co/api/models/black-forest-labs/FLUX.2-dev/tree/main" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for f in d:
        if f['path'].endswith('.safetensors') and ('ae' in f['path'].lower() or 'vae' in f['path'].lower()): print(f['path']); break
except Exception: pass")
  echo "vae : $VAEP"
  python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='black-forest-labs/FLUX.2-dev', filename='$VAEP', local_dir='$HOME/flux-tmp/w')
print('vae OK')"
  find "$HOME/flux-tmp/w" -type f -exec du -h {} \;

  DIFFP=$(find "$HOME/flux-tmp/w" -name "*.gguf" | grep -i klein | head -1)
  LLMP=$(find "$HOME/flux-tmp/w" -name "*Qwen3-4B*.gguf" | head -1)
  VAEPF=$(find "$HOME/flux-tmp/w" -name "*.safetensors" | grep -iE "ae|vae" | head -1)
  echo "DIFFP=$DIFFP"; echo "LLMP=$LLMP"; echo "VAEPF=$VAEPF"

  echo ""
  echo "--- 3) GÉNÉRATION (4 steps, 768x512, 4 threads) ---"
  timeout 1200 "$SD" \
    --diffusion-model "$DIFFP" \
    --vae "$VAEPF" \
    --llm "$LLMP" \
    -p "an orange tabby cat walking through a sunlit forest, warm golden sunlight rays filtering through the trees, photorealistic, highly detailed" \
    --cfg-scale 1.0 --steps 4 --sampling-method euler \
    -W 768 -H 512 --threads 4 --diffusion-fa --offload-to-cpu \
    -o "$HOME/flux-tmp/chat-roux.png" 2>&1 | tail -18
  RC=$?
  echo "(code génération=$RC)"
  ls -la "$HOME/flux-tmp/"*.png 2>/dev/null

  echo ""
  echo "--- 4) publication + purge ---"
  if [ -f "$HOME/flux-tmp/chat-roux.png" ]; then
    cp "$HOME/flux-tmp/chat-roux.png" "$GITHUB_WORKSPACE/bridge/artifacts/chat-roux-foret.png"
    echo "IMAGE PUBLIÉE : bridge/artifacts/chat-roux-foret.png ($(du -h "$GITHUB_WORKSPACE/bridge/artifacts/chat-roux-foret.png" | cut -f1))"
  else
    echo "❌ pas d'image — dernières lignes:"
    timeout 1200 "$SD" --help >/dev/null 2>&1 || true
  fi
  rm -rf "$HOME/flux-tmp" && echo "purgé ✓ (éphémère, comme demandé)"
  echo "durée totale : $(( $(date +%s) - T0 )) s"
  echo "===== FIN ====="
} 2>&1
exit 0
