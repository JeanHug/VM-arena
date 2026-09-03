{
  echo "===== [ACTION] GÉNÉRATION v4 — chat roux forêt (VAE miroir Comfy + libs complètes) ====="
  echo "# host: $(hostname) | début: $(date -u +%FT%TZ)"
  cd "$HOME/persist" || exit 1
  mkdir -p "$HOME/flux-tmp/bin" "$HOME/flux-tmp/w" "$GITHUB_WORKSPACE/bridge/artifacts"
  T0=$(date +%s)
  pip3 install -q -U huggingface_hub 2>/dev/null

  echo "--- 1) binaire + TOUTES les libs du zip ---"
  curl -sL --retry 2 --max-time 300 -o /tmp/sd.zip "https://github.com/leejet/stable-diffusion.cpp/releases/download/master-841-6b3edaa/sd-master-6b3edaa-bin-Linux-Ubuntu-24.04-x86_64.zip"
  rm -rf /tmp/sdx && python3 -c "import zipfile; zipfile.ZipFile('/tmp/sd.zip').extractall('/tmp/sdx')"
  find /tmp/sdx -type f -exec cp {} "$HOME/flux-tmp/bin/" \;
  export LD_LIBRARY_PATH="$HOME/flux-tmp/bin:${LD_LIBRARY_PATH:-}"
  SD="$HOME/flux-tmp/bin/sd-cli"
  [ -x "$SD" ] || SD=$(find "$HOME/flux-tmp/bin" -name 'sd-cli' | head -1)
  chmod +x "$SD"
  echo "binaire : $SD"
  "$SD" --version 2>&1 | head -2 || { echo "❌ binaire ne démarre pas"; ls -la "$HOME/flux-tmp/bin"; exit 1; }

  echo "--- 2) poids (diffusion + qwen3-4b + VAE miroir non-gated) ---"
  python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='leejet/FLUX.2-klein-4B-GGUF', filename='flux-2-klein-4b-Q4_0.gguf', local_dir='$HOME/flux-tmp/w')
print('diffusion OK')"
  python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='unsloth/Qwen3-4B-GGUF', filename='Qwen3-4B-Q4_K_M.gguf', local_dir='$HOME/flux-tmp/w')
print('qwen3-4b OK')"

  echo "--- sonde VAE miroir (candidats en Python, premier qui marche) ---"
  VAERES=$(python3 - <<'PYV'
from huggingface_hub import hf_hub_download
cands = [
    ("Comfy-Org/vae-text-encorder-for-flux-klein-4b", "split_files/vae/flux2-vae.safetensors"),
    ("Comfy-Org/vae-text-encorder-for-flux-klein-4b", "flux2-vae.safetensors"),
    ("Comfy-Org/flux2-klein-4B", "split_files/vae/flux2-vae.safetensors"),
    ("Comfy-Org/flux2-klein-4B", "split_files/vae/ae.safetensors"),
]
import os
for repo, fn in cands:
    try:
        p = hf_hub_download(repo_id=repo, filename=fn, local_dir=os.environ["HOME"] + "/flux-tmp/w/vae")
        print("OK|" + p)
        break
    except Exception as e:
        print("essai rate:", repo, fn, type(e).__name__)
PYV
)
  echo "$VAERES" | tail -3
  VAEPF=$(echo "$VAERES" | grep "^OK|" | head -1 | cut -d'|' -f2)
  [ -z "$VAEPF" ] && { echo "❌ aucun VAE téléchargeable"; exit 1; }
  echo "VAE final : $VAEPF"

  find "$HOME/flux-tmp/w" -type f -name "*.gguf" -exec du -h {} \;
  find "$HOME/flux-tmp/w/vae" -type f -exec du -h {} \;

  DIFFP=$(find "$HOME/flux-tmp/w" -name "*klein*.gguf" | head -1)
  LLMP=$(find "$HOME/flux-tmp/w" -name "*Qwen3-4B*.gguf" | head -1)
  VAEPF=$(find "$HOME/flux-tmp/w/vae" -name "*.safetensors" | head -1)
  echo "DIFFP=$DIFFP"; echo "LLMP=$LLMP"; echo "VAEPF=$VAEPF"

  echo ""
  echo "--- 3) GÉNÉRATION (4 steps, 768x512) ---"
  timeout 1200 "$SD" \
    --diffusion-model "$DIFFP" \
    --vae "$VAEPF" \
    --llm "$LLMP" \
    -p "an orange tabby cat walking through a sunlit forest, warm golden sunlight rays filtering through the trees, photorealistic, highly detailed" \
    --cfg-scale 1.0 --steps 4 --sampling-method euler \
    -W 768 -H 512 --threads 4 --diffusion-fa --offload-to-cpu \
    -o "$HOME/flux-tmp/chat-roux.png" 2>&1 | tail -15
  RC=$?
  echo "(code=$RC)"
  ls -la "$HOME/flux-tmp/"*.png 2>/dev/null

  echo ""
  echo "--- 4) publication + purge ---"
  if [ -s "$HOME/flux-tmp/chat-roux.png" ]; then
    cp "$HOME/flux-tmp/chat-roux.png" "$GITHUB_WORKSPACE/bridge/artifacts/chat-roux-foret.png"
    echo "IMAGE PUBLIÉE : bridge/artifacts/chat-roux-foret.png ($(du -h "$GITHUB_WORKSPACE/bridge/artifacts/chat-roux-foret.png" | cut -f1))"
  else
    echo "❌ pas d'image générée"
  fi
  rm -rf "$HOME/flux-tmp" && echo "purgé ✓ (éphémère)"
  echo "durée totale : $(( $(date +%s) - T0 )) s"
  echo "===== FIN ====="
} 2>&1
exit 0
