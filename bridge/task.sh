echo "TEST DE FUMÉE DU WRAPPER GÉNÉRIQUE"
echo "node: $(hostname) | $(nproc) cœurs"
echo "moteur persistant : $(bin/llama-cli --version 2>&1 | head -1 || echo absent)"
