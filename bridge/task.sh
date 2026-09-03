{
  echo "===== [ACTION] FLUX.2 KLEIN 4B — génération image (éphémère) ====="
  echo "# host: $(hostname) | date: $(date -u +%FT%TZ)"
  PROMPT="an orange tabby cat walking through a sunlit forest, warm golden sunlight rays filtering through trees, photorealistic, high detail"
  cd "$HOME/persist" || exit 1
  pip3 install -q -U huggingface_hub 2>/dev/null
  mkdir -p "$HOME/flux-tmp"

  echo "--- 1) reconnaissance des dépôts flux.2-klein ---"
  curl -sL --max-time 30 "https://huggingface.co/api/models?search=flux.2-klein&limit=40" | python3 -c "
import json,sys
try:
    for m in json.load(sys.stdin): print('  ', m['id'], m.get('downloads',0))
except Exception as e: print('  erreur search:', e)" | head -15

  echo "--- 2) stable-diffusion.cpp : releases ? ---"
  SDREL=$(curl -sL --max-time 30 "https://api.github.com/repos/leejet/stable-diffusion.cpp/releases/latest")
  echo "$SDREL" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print('  tag:', d.get('tag_name'))
    for a in d.get('assets',[]):
        if 'linux' in a['name'].lower() and 'x64' in a['name'].lower(): print('   asset:', a['name'])
except Exception as e: print('  erreur release:', e)"
  echo "$SDREL" | grep -o '"tag_name": *"[^"]*"' | head -1

  echo "--- 3) GGUF klein sur HF ? ---"
  for SR in "flux.2-klein-gguf" "flux.2 klein gguf"; do
    curl -sL --max-time 30 "https://huggingface.co/api/models?search=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote('$SR'))")&limit=15" | python3 -c "
import json,sys
try:
    for m in json.load(sys.stdin): print('  GGUF?', m['id'])
except Exception: pass" | head -8
  done

  echo ""
  echo "--- 4) vérif support FLUX.2 dans sd.cpp (README master) ---"
  curl -sL --max-time 30 "https://raw.githubusercontent.com/leejet/stable-diffusion.cpp/master/README.md" | grep -iE "flux.2|flux2|klein" | head -5 || echo "(pas de mention FLUX.2 trouvée)"

  echo ""
  echo "===== FIN DE LA RECONNAISSANCE (décision à l'étape 2) ====="
} 2>&1
exit 0
