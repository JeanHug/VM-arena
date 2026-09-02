#!/usr/bin/env bash
# ============================================================
# bridge-agent.sh — passerelle Codespace <-> VM Arena
#
# À lancer DANS le Codespace (une seule fois) :
#   nohup bash bridge-agent.sh > /tmp/vm-bridge.log 2>&1 &
#
# Fonctionnement :
#   1. Surveille bridge/cmd.txt sur la branche distante BRANCH
#   2. Dès qu'un NOUVEAU cmd.txt apparaît (hash différent), l'exécute
#   3. Pousse le résultat dans bridge/out.txt sur la même branche
#
# Pour l'arrêter :
#   pkill -f bridge-agent.sh
# ============================================================
set -u

BRANCH="arena/01a061e4-vm-arena"
POLL_SECONDS=5
LOGTAG="[vm-bridge]"

echo "$LOGTAG agent démarré sur $(hostname) — $(date -Is)"
echo "$LOGTAG branche surveillée : origin/$BRANCH (bridge/cmd.txt)"

LAST_HASH=""

while true; do
    # Récupère la dernière version de la branche
    if ! git fetch origin "$BRANCH" --quiet 2>/dev/null; then
        echo "$LOGTAG erreur: fetch impossible — $(date -Is)"
        sleep "$POLL_SECONDS"
        continue
    fi

    # Hash du cmd.txt distant (vide si absent)
    CMD_HASH="$(git show "origin/$BRANCH:bridge/cmd.txt" 2>/dev/null | md5sum | cut -d' ' -f1)"

    if [ -n "$CMD_HASH" ] && [ "$CMD_HASH" != "$LAST_HASH" ]; then
        LAST_HASH="$CMD_HASH"
        echo "$LOGTAG nouvelle commande détectée ($CMD_HASH) — $(date -Is)"

        # Extrait et exécute la commande
        git show "origin/$BRANCH:bridge/cmd.txt" > bridge/.cmd.sh 2>/dev/null || {
            echo "$LOGTAG erreur: lecture cmd.txt impossible"
            continue
        }

        {
            echo "=== VM-BRIDGE RESULT ==="
            echo "# host: $(hostname)"
            echo "# date: $(date -Is)"
            echo "# cmd_hash: $CMD_HASH"
            echo "# --- stdout/stderr ---"
            bash bridge/.cmd.sh 2>&1
            echo "# --- fin ---"
            echo "EXIT_CODE=$?"
        } > bridge/out.txt

        rm -f bridge/.cmd.sh

        # Publie le résultat (avec rebase + retries pour éviter les collisions)
        git add bridge/out.txt
        git -c user.name="codespace-bridge" -c user.email="bridge@codespace.local" \
            commit -m "bridge: resultat cmd $CMD_HASH" --quiet || {
            echo "$LOGTAG rien à committer"
            continue
        }

        PUSHED=0
        for attempt in 1 2 3 4 5; do
            git pull --rebase origin "$BRANCH" --quiet 2>/dev/null
            if git push origin "HEAD:$BRANCH" --quiet 2>/dev/null; then
                PUSHED=1
                echo "$LOGTAG résultat publié — $(date -Is)"
                break
            fi
            sleep 3
        done
        [ "$PUSHED" = "0" ] && echo "$LOGTAG erreur: push impossible après 5 essais"
    fi

    sleep "$POLL_SECONDS"
done
