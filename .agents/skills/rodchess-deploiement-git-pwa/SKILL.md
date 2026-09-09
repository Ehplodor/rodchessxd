---
name: rodchess-deploiement-git-pwa
description: >-
  Référentiel du déploiement RodChessXD : carte des branches locales (main/main-iOS/main-web) vs GitHub,
  cycle de vie de la PWA Web sur GitHub Pages (export Godot, workflow Actions), processus sûr d'intégration
  (cherry-pick, jamais de merge main-iOS→main-web), fichiers secrets/binaires à ne JAMAIS pousser.
  À charger systématiquement pour toute mise à jour sur main-iOS ou main-web, toute fusion ou tout déploiement.
---

# RodChessXD — Déploiement, branches & fusions

Référentiel à consulter **à chaque MàJ** (travail sur `main-iOS` ou `main-web`, fusion, export Web, déploiement itch/GitHub Pages).

---

## 1. Carte des branches (état de référence)

| Branche | Lieu | HEAD | Rôle |
| --- | --- | --- | --- |
| `main` | **local uniquement** | `f43bbed` | Archive locale (contient secrets/binaires dans l'historique). **Jamais poussée.** |
| `main-iOS` | **local uniquement** | `63a80c1` | Bac à sable features natives (Windows/Android/iOS) + packagé Windows « avec Maia ». Contient keystores/binaires dans l'historique. **Jamais poussée.** |
| `main-web` | **local** = `origin/main` | `47b03ea` | Branche de travail **propre et publique** (sans secrets/binaires versionnés). Source de vérité pour le dépôt. |
| `main` (remote) = `origin/main` | **GitHub** (`https://github.com/Ehplodor/rodchessxd.git`) | `47b03ea` | Unique branche distante. Branche par défaut. Chaque `push` → redéploiement GitHub Pages. |
| `main2` | supprimée | — | Obsolète, supprimée. |

Règle d'or : **seule `main-web` (poussée vers `origin/main`) est publiée.** Tout le reste vit en local.

---

## 2. Pourquoi il ne faut JAMAIS faire un merge `main-iOS → main-web`

- L'historique public a été **réécrit et purgé** (`git filter-repo`) des secrets et binaires lors de la 1ʳᵉ mise en ligne : les SHAs de `main-web`/`origin/main` **n'ont aucun ancêtre commun** avec ceux de `main`/`main-iOS` (histoires « unrelated »).
- Un merge ramènerait donc : conflits massifs, ré-import des **keystores et binaires** dans l'arbre/la publication.
- `main`/`main-iOS` contiennent **de vrais secrets** (2 keystores de signature Android) : les exposer serait critique.

→ Toute intégration passe par un **port ciblé** (cherry-pick ou copie de fichiers), jamais par `git merge`.

---

## 3. Fichiers protégés — à ne JAMAIS committer ni pousser

Rappel des règles déjà présentes dans `.gitignore`. Vérifier qu'aucun n'apparaît dans `git diff --cached --name-only` avant chaque push.

```
release.keystore                      # secret signature Android
android/rodchess.keystore
bin/*.exe  bin/*.dll  bin/*.pb.gz      # moteurs locaux (stockfish/lc0/maia/791556)
addons/RodChessUci/bin/                # AAR du plugin (régénérés)
android/build/libs/**                  # .so / godot-lib*.aar
android/build/src/main/jniLibs/**      # libstockfish.so
stockfish.js  uci_worker_bridge.js     # doublons racine (canoniques : assets/web/)
RodChessXD2_Windows*.exe  RodChessXD2_Windows*.zip
dist/                                  # export PWA local / CI
```

> Ces fichiers peuvent rester **sur le disque** (nécessaires aux exports Desktop/Android locaux) : ils doivent être simplement **non suivis + ignorés**.

---

## 4. Flux normal de mise à jour (recommandé : tout se fait sur `main-web`)

1. Se placer et vérifier :
   ```bash
   git checkout main-web
   git status            # propre (seuls fichiers protégés ignorés, invisibles)
   ```
2. Modifier les sources (moteur, UI, docs…). **Ne jamais** faire `git add -A` : ajouter explicitement les chemins utiles.
   ```bash
   git add src/... export_presets.cfg README.md
   ```
3. Commit (style repo : messages français courts et précis).
4. Push **vers `main` distant uniquement** :
   ```bash
   git push origin main-web:main        # MÀJ de origin/main + redéploiement Pages
   ```
   ⚠️ Ne PAS faire `git push origin main-web` (créerait une branche distante `main-web` parasite).
5. Aller sur GitHub → Actions → **Deploy RodChessXD PWA** : `build` puis `deploy` doivent passer.
6. Valider la PWA (voir §7).

> Astuce déclenchement manuel : `git commit --allow-empty -m "ci: trigger deploy" && git push origin main-web:main`.

---

## 5. Intégrer du travail fait sur `main-iOS` (port ciblé, jamais de merge)

Cas : une feature n'existe que sur `main-iOS` et doit rejoindre la publication.

### 5.1 Préparer
```bash
git fetch --all
git checkout main-iOS   # repérer le(s) commit(s) concerné(s)
git log --oneline -10
# noter le SHA du commit source (ex. a1b2c3d)
```

### 5.2 Cherry-pick propre sur main-web
```bash
git checkout main-web
git cherry-pick -n a1b2c3d        # -n : n'engage pas le commit, pour neutraliser d'abord
```

### 5.3 Neutraliser les fichiers protégés s'ils ont été touchés
Si le commit modifiait un chemin protégé (§3) — sinon passer cette étape :
```bash
git restore --staged --worktree \
  release.keystore android/rodchess.keystore \
  bin/ android/build/libs android/build/src/main/jniLibs addons/RodChessUci/bin \
  stockfish.js uci_worker_bridge.js
```
(`--staged` retire de l'index ; `--worktree` laisse les fichiers sur disque = ignorés → jamais poussés.)

### 5.4 Vérifier puis committer
```bash
git status
git diff --cached --name-only      # NE doit contenir AUCUN chemin protégé (§3)
# examen du diff source :
git diff --cached
git commit -m "port(iOS→web): <description du changement>"
```

### 5.5 Pousser
```bash
git push origin main-web:main
```

### Gestion des conflits / cas particuliers
- **Conflit de cherry-pick** : résoudre dans les fichiers, puis `git add <fichiers>` et `git commit` (le cherry-pick `-n` laisse l'état indexé prêt).
- **Dépendances entre commits iOS** : les cherry-picker dans l'ordre.
- **Dossier entier à récupérer** (ex. nouvelle classe `src/...`) : copie manuelle puis `git add`, plus simple qu'un merge.

---

## 6. Déploiement Web / PWA (rappel du process)

### 6.1 Export Web local (validation avant publication)
```bash
# Icônes PWA (une seule fois après modif d'icon.svg)
godot --headless --path . --import
godot --headless --path . --script res://tools/render_pwa_icons.gd

# Export vers dist/ (dossier créé avant l'export)
rm -rf dist && mkdir dist
godot --headless --path . --export-release "Web" dist/index.html
cp assets/web/uci_worker_bridge.js assets/web/stockfish.js dist/
python tools/patch_pwa_sw.py dist/index.service.worker.js   # pré-cache moteur WASM (hors-ligne)
```
Lancer en local : `python -m http.server 8060 -d dist` puis ouvrir `http://localhost:8060/`.

### 6.2 Publication CI (automatique)
- Fichier : `.github/workflows/deploy-web.yml`.
- Déclencheurs : `push` sur `main` + `workflow_dispatch`.
- Étapes : télécharge Godot 4.7.1 + templates → `--import` → `mkdir -p dist` → export Web → copie des 2 `.js` → patch SW → `upload-pages-artifact` → `deploy-pages`.
- Une seule fois : `Settings → Pages → Source: GitHub Actions` + **approuver l'environnement `github-pages`** à la 1ʳᵉ exécution.

### 6.3 PWA (points de config importants — `export_presets.cfg`, preset `Web`)
- `progressive_web_app/enabled=true`, `display=standalone`, icônes `icon-144/180/512` (générées).
- `html/experimental_virtual_keyboard=true` → indispensable à la **saisie clavier mobile** (Android/iOS) dans les champs (LineEdit/TextEdit). Sans ça : OSK ouverte mais aucune touche transmise.
- `variant/thread_support=false` (mono-thread) car GitHub Pages n'envoie pas COOP/COEP.
- `exclude_filter="dist/*"` (évite d'empaqueter le build dans le PCK).

### 6.4 Pièges connus (bénins / à connaître)
- Warning **Node 20 déprécié** : non bloquant (actions `checkout@v4`, `upload-pages-artifact@v3`).
- `cannot connect to daemon tcp:5037` : bruit adb/Android, sans effet.
- Erreur police `NotoSans` au 1ᵉʳ `--import` : attendue (import non terminé), non bloquante.
- `dist` doit exister avant `--export-release` (géré par le workflow).

### 6.5 itch.io
- Le dossier Windows est un livrable séparé (exe/zip locaux, §3 — jamais dans le repo public).
- Copie de la page prête à coller : `docs/ITCH_PAGE_COPY.md` (Windows + lien vers la PWA + AI disclosure).
- `README.md` du dépôt contient la **matrice features** honnête Web vs Desktop.

---

## 7. Validation post-déploiement (checklist)

Sur `https://ehplodor.github.io/rodchessxd/` :
1. Chargement + démarrage du moteur (« Stockfish démarré », console F12).
2. Installation PWA (icône « Installer » Chrome/Edge).
3. **Hors-ligne** : 1ᵉʳ chargement en ligne, puis DevTools → Network → Offline → rechargement : l'app **et l'analyse** marchent.
4. MàJ après un nouveau push : le service worker doit se rafraîchir au rechargement.
5. **Mobile** : saisie d'un pseudo (champs LineEdit) doit fonctionner (clavier virtuel).

---

## 8. Checklist « avant de pousser » (à ne jamais sauter)

- [ ] Je suis sur `main-web` (`git branch --show-current` = `main-web`).
- [ ] `git status` propre (aucun secret/binaire indexé ; ils sont ignorés).
- [ ] `git diff --cached --name-only` ne contient aucun chemin protégé (§3).
- [ ] `git ls-remote origin` ne montre que `refs/heads/main` (= HEAD local).
- [ ] J'ai poussé avec `git push origin main-web:main` (jamais `git push origin main-web`).
- [ ] Actions : `build` + `deploy` verts ; PWA revalidée (§7) si changement impactant.
