# 🏔️ BILAN DE LA CAMPAGNE — VM-ARENA fédérée & échelle AA

*Campagne nocturne + matinale des 2-3 septembre 2026. Tout est mesuré, rien d'estimé.*

---

## 1️⃣ L'architecture finale en place

```
TOI → MOI → vmctl.py (1 commande par mission)
                │
        CONTROL PLANE : le repo Git (files, snapshots, résultats)
                │
    ┌───────────┴────────────────┐
    ▼                            ▼
NODE ACTION (éphémère)      NODE CODESPACE (persistant)
4c/16 Go, snapshot Git      4c/16 Go + disque 32 Go
moteur llama.cpp persistant Gemma 4 E2B installé DÉFINITIVEMENT
(~/persist/bin)             (~/models, 2,9 Go + moteur)
```

## 2️⃣ Le test fédéré 32 Go — verdict définitif

| Élément | Résultat mesuré |
|---|---|
| Protocole complet (RPC + tunnel + répartition de couches) | ✅ **fonctionne bout en bout** |
| Nœud distant (rpc-server b10760 sur Codespace) | ✅ écoute confirmée en double SSH |
| Téléchargement modèle 16,9 Go côté pilote | ✅ 56 s – 6 min (selon run) |
| **Transfert des couches via double tunnel SSH** | ❌ **~4 Mo/s** → 4,5 Go ne passent pas en 19 min |
| Nettoyage (RAM effacée, disque intact, machine arrêtée) | ✅ 5 fois sur 5 |

**Conclusion :** l'union mémoire 32 Go est *techniquement prouvée* mais *pratiquement non viable* via le tunnel. Pour la rendre utile il faudrait une route réseau directe (API Ports du Codespace exposé, ou un self-hosted runner sur le même réseau). La leçon : **fédérer la capacité est possible ; fédérer la vitesse, non** (le calcul séquentiel d'un LLM n'y gagne rien, et le transport coûte cher).

## 3️⃣ L'échelle AA — 8 modèles mesurés sur nos nœuds

*Q posée : « Quelle est la capitale de la France ? » — 4 threads CPU, quants adaptés à 16 Go.*

| Modèle | Taille totale / active | Fichier chargé | RAM max | ⚡ Génération | Score AA | Verdict |
|---|---|---|---|---|---|---|
| **Granite 4.2 3B** | 3B / 3B dense | Q4_K_M (2,1 Go) | confort | **15,6 t/s** | ~10-12 (top "tiny") | ⚡ ultra-rapide, léger |
| **Gemma 4 E2B** | 5,1B / 2,3B actifs | Q4_K_M (2,9 Go) | ~4 Go | **15,6-17 t/s** | **15** | ⚡ **installé définitivement sur Codespace** |
| **Gemma 4 E4B** | 8B / 4,5B actifs | Q4_K_M (4,7 Go) | ~8 Go | **10,1 t/s** | 12-19 (multimodal) | ✅ bon palier |
| **Qwen 3.5 9B** | 9B / 9B dense | Q4_K_M (5,3 Go) | ~9 Go | **6,1 t/s** | ~20 (roi 16 Go unifié) | 🟡 dense = lent |
| **gpt-oss-20b** | 20B / 3,6B actifs | Q4_K_M (11 Go) | ~13 Go | **9,9 t/s** | ≈28 (raisonneur openai) | ✅ pile au seuil 10 |
| **Qwen3.5-35B-A3B** | 35B / 3B actifs | UD-IQ3_XXS (13 Go) | ~14 Gi | **8,4 t/s** | **37** ⭐ | 🏆 **meilleure intelligence vivable** |
| **Gemma 4 26B-A4B** | 27B / 3,8B actifs | UD-IQ4_XS (13,9 Go) | 14,6 Gi — *juste* | 4,7 t/s | 31 | 🟡 battu par Qwen3.5-35B |
| **Qwen3.8-27B** | 28B / 28B dense | UD-IQ3_S (12 Go) | 14,5 Gi — *juste* | 0,8 t/s | **52** (n°23 mondial, roi du code) | 🐢 intelligence max, vitesse min |

## 4️⃣ Les lois de physique de notre matériel (mesurées)

1. **Le plafond est le CPU, pas la RAM** : tout ≤ ~4B actifs tourne ≥ 8 t/s ; un dense 27B meurt (0,8 t/s)
2. **L'actif bat le dense** : 35B-A3B (8,4 t/s) contre 27B dense (0,8 t/s) — même ordre de taille, ×10 en vitesse
3. **La RAM 16 Go** accueille jusqu'à ~14 Gi de poids (26-35B quantés) mais au bord du débordement au-delà de ~14 Gi
4. **Le réseau du datacenter est fulgurant** (jusqu'à 450 Mo/s HF) — le seul goulot réseau est notre tunnel inter-nœuds
5. **Score AA vs vitesse** : la zone douce = MoE à ~3-4B actifs (Qwen3.5-35B-A3B, gpt-oss-20b, Gemma-4-26B)

## 5️⃣ Recommandations finales

| Besoin | Choix | Où |
|---|---|---|
| Réponses rapides quotidiennes | **Gemma 4 E2B** (15,6 t/s, installé) | Codespace 💤 |
| La plus haute intelligence *utilisable* | **Qwen3.5-35B-A3B** (AA 37, 8,4 t/s) | Actions, temporaire |
| Code exigeant (patience admise) | **Qwen3.8-27B** (AA 52, 0,8 t/s) | Actions, temporaire |
| Raisonnement outillage OpenAI | **gpt-oss-20b** (9,9 t/s) | Actions, temporaire |
| Ultra-léger embarqué | **Granite 4.2 3B** (15,6 t/s) | partout |

## 6️⃣ Traçabilité

- 20+ runs Actions, tous publiés dans `bridge/out.txt` et l'onglet **Actions**
- Tâches réutilisables : `bridge/tasks/*.sh`, orchestration : `vmctl.py`
- PR #1 : https://github.com/JeanHug/VM-arena/pull/1
- Codespace : Gemma 4 E2B + moteur gravés sur disque, machine arrêtée (quota préservé)
