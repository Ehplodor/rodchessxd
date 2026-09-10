---
name: rodchess-exports-multi-plateformes
description: >-
  Guide des exports RodChessXD (Web/PWA, Windows, Android) : commandes exactes, spécificités et pièges
  par plateforme, difficultés rencontrées et solutions trouvées (service worker hors-ligne, serveur local
  mono-thread, moteur embarqué Windows, démarrage Live/engine_ready, flèches du meilleur coup), vérifications
  post-export et hygiène git. À charger avant tout export, reconstruction de livrable ou diagnostic de build.
---

# RodChessXD — Exports multi-plateformes (Web, Windows, Android)

Référentiel des exports. À charger **avant tout export**, reconstruction de livrable ou diagnostic de build.

## 1. Outils et prérequis

- **Godot 4.7.1 (console)** : `C:\Dev\tools\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe`
- **Android SDK build-tools 36.1.0** : `%LOCALAPPDATA%\Android\Sdk\build-tools\36.1.0` (sous PowerShell : `$env:LOCALAPPDATA\Android\Sdk\build-tools\36.1.0` ; `aapt.exe`, `apksigner.bat`)
- **Python** (imports, patch service worker, tests d'intégrité)
- **Keystores locaux** (jamais dans le dépôt) : `release.keystore`, `android/rodchess.keystore`
- **Moteurs locaux** : `bin/` (stockfish.exe, lc0.exe, DLL, maia-*.pb.gz) — présents seulement en dev
- **Branch de travail** : `main-web` (cf. skill `rodchess-deploiement-git-pwa`)

## 2. Vue d'ensemble

| Plateforme | Preset | Sortie | Spécificités clés | Livrable |
|---|---|---|---|---|
| Web / PWA | `Web` | `dist/index.*` (CI) et racine `RodChessXD2.*` (local) | mono-thread, PWA, service worker, bridge JS moteur | `dist/` publié ; racine pour `Lancer_Web.bat` |
| Windows | `Windows Desktop` | `RodChessXD2_Windows.exe` | PCK embarqué + `include_filter="bin/*"` | exe + `bin/` + LICENSE + NOTICE dans un zip |
| Android | `Android` | `RodChessXD2.apk` | gradle build, arm64-v8a, release signé | APK (local, non publié) |

Règle générale : **ne jamais committer/pousser** pendant un export ; ne modifier que les sources nécessaires ; vérifier `git status` avant/après.

## 3. Web / PWA

### 3.1 Build `dist/` (publication / CI)
```bash
godot --headless --path . --import
# vider dist/ (python shutil), puis :
godot --headless --path . --export-release "Web" dist/index.html
cp assets/web/uci_worker_bridge.js assets/web/stockfish.js dist/
python tools/patch_pwa_sw.py dist/index.service.worker.js
```
- `export_presets.cfg` (preset Web) : `exclude_filter="dist/*,bin/*"` (ne pas embarquer le build ni les binaires Windows), `thread_support=false` (GitHub Pages ne renvoie pas COOP/COEP), PWA activée, clavier virtuel expérimental, icônes.
- Le service worker `CACHEABLE_FILES` (`*.wasm`, `*.pck`) est généré par Godot ; `patch_pwa_sw.py` ajoute `stockfish.js` + `uci_worker_bridge.js` au **pré-cache** (`CACHED_FILES`) pour le moteur hors-ligne.

### 3.2 Build racine (harnais local `Lancer_Web.bat`)
`serve_web.py` sert la **racine** et ouvre `http://localhost:8060/RodChessXD2.html`.
```bash
godot --headless --path . --export-release "Web"          # export_path preset = ./RodChessXD2.html
cp assets/web/uci_worker_bridge.js assets/web/stockfish.js ./
python tools/patch_pwa_sw.py RodChessXD2.service.worker.js
```
- `RodChessXD2.service.worker.js` est **suivi par git** (contrairement à `.html/.js/.wasm/.pck` ignorés). Après chaque **ré-export racine**, relancer le patch (l'export régénère le SW sans le patch).
- `serve_web.py` doit être **multi-thread** (`ThreadingTCPServer`) : un serveur mono-thread sérialise les requêtes et le navigateur (plusieurs connexions parallèles pour wasm/pck/js) reste **bloqué au chargement**.

### 3.3 Pièges Web
- Un service worker obsolète peut servir un ancien build cassé : faire `Ctrl+Shift+R` ou *DevTools → Application → Clear storage* lors des tests.
- Vérifier les artefacts : `.wasm` commence par `00 61 73 6d`, `.pck` par `GDPC` ; tailles attendues ~39 Mo (.wasm) et ~2-3 Mo (.pck).
- Ne pas tester le Web avec `python -m http.server` en mono-thread pour un gros build ; préférer `serve_web.py` (multi-thread).

## 4. Windows

### 4.1 Build
```powershell
Stop-Process -Name RodChessXD2_Windows -Force -ErrorAction SilentlyContinue
Remove-Item RodChessXD2_Windows.tmp -ErrorAction SilentlyContinue
& "C:\Dev\tools\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" ./RodChessXD2_Windows.exe
```
- Preset : `binary_format/embed_pck=true`, `include_filter="bin/*"` → les moteurs sont **embarqués dans l'exe** ; `EngineManager` est censé les extraire vers `user://engines/` au 1er lancement.
- Aligner `application/file_version` et `application/product_version` sur `project.godot` (`config/version`).

### 4.2 Problème connu — moteur non lancé sans `bin/`
L'extraction `user://engines/` **ne se déclenche pas** dans l'export (chemin `res://bin/...` globalisé en relatif). Sans dossier `bin/` à côté de l'exe, le moteur échoue (`Could not create child process: bin/stockfish.exe`).
**Solution de livraison** : packager `RodChessXD2_Windows.exe` **avec** `bin/` complet + `LICENSE` + `NOTICE.md` dans un dossier, puis zipper (`RodChessXD2_Windows_v<version>.zip`, racine unique). (Correctif de fond possible côté `EngineManager`, non appliqué.)

### 4.3 Vérifications
- `(Get-Item .\RodChessXD2_Windows.exe).VersionInfo.FileVersion` = version attendue ; taille ~258 Mo.
- Test de fumée depuis le dossier de distribution : `& ".\RodChessXD2_Windows.exe" --headless --quit-after 600` → doit afficher `Lancement de Stockfish` et `[brut] Stockfish`, sans `Could not create child process`.

## 5. Android

### 5.1 Build
```powershell
& "C:\Dev\tools\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --export-release "Android" ./RodChessXD2.apk
```
- Preset : arm64-v8a (seul), `use_gradle_build=true`, `export_format=0` (APK), `package/signed=true`, `exclude_filter="bin/*"` (ne pas embarquer les binaires Windows dans l'APK ; le moteur vient de `lib/arm64-v8a/libstockfish.so` via jniLibs).
- Version : aligner `version/name` sur `project.godot` et incrémenter `version/code`.

### 5.2 Signature
Les champs `keystore/release` **ne sont pas dans `export_presets.cfg`** sur `main-web` (dépôt public nettoyé) : l'export release utilise le keystore configuré dans les **réglages de l'éditeur**. **Ne jamais** ajouter de keystore/mot de passe au dépôt.

### 5.3 Pièges Android
- Le build gradle dure **10-20 min sans sortie** : ne pas conclure à un blocage. Lancer en détaché avec journal et attendre (boucle de polling) ; nettoyer d'éventuels démons (`android\build\gradlew.bat --stop`, `Stop-Process -Name java`).
- Un export **interrompu peut avoir malgré tout produit** l'APK : toujours comparer l'horodatage de `RodChessXD2.apk` à celui des sources avant de relancer.
- Ne pas empiler deux builds gradle (locks).

### 5.4 Vérifications
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.1.0\aapt.exe" dump badging .\RodChessXD2.apk
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.1.0\apksigner.bat" verify --print-certs .\RodChessXD2.apk
```
Attendu : `versionName` = version courante, `versionCode` cohérent, `native-code: 'arm64-v8a'`, `lib/arm64-v8a/libstockfish.so` + `libgodot_android.so` présents (Python `zipfile`), 1 signataire (`CN=RodChessXD`), taille ~105 Mo. Le package reste le placeholder `com.votreapp.rodchess` (à changer pour une publication Play).

## 6. Difficultés rencontrées et solutions

| Difficulté | Cause | Solution |
|---|---|---|
| Live absent au lancement (desktop) | `engine_ready` émis **avant** la poignée de main UCI (`uciok`/`readyok`) ; `is_evaluating` restait bloqué | Émettre `engine_ready` **après `readyok`**, sur le **thread principal** (`_process`), bufferiser la demande Live (`_pending_live_fen`) et réarmer l'état |
| Web OK mais desktop KO (mêmes symptômes) | `call_deferred` émis depuis le **thread de lecture UCI** peu fiable ; Web l'émet depuis le thread principal | Ne jamais émettre de signal UI depuis le thread de lecture ; passer par un poll `_process` côté main thread |
| Flèches du meilleur coup absentes/intermittentes | `reset_board_visuals()` remettait la flèche à `-1` sur les rafraîchissements | Lier la flèche au **FEN** (`best_move_arrow_fen`) + helper unique `set_best_move_arrow()` ; n'effacer que si la position change |
| Web bloqué au chargement | `serve_web.py` **mono-thread** sérialisait les requêtes parallèles | Passer à `ThreadingTCPServer` |
| Moteur hors-ligne absent en PWA | Le SW généré n'inclut pas les JS du moteur | `tools/patch_pwa_sw.py` (détection regex de `CACHED_FILES`, idempotent, gère `index.*` **et** `RodChessXD2.*`) |
| Windows : moteur KO sur une machine propre | Extraction `user://engines` non déclenchée (chemin globalisé relatif) | Livrer le zip **avec `bin/`** à côté de l'exe (ou corriger l'extraction) |
| Android « bloqué » | Build gradle long et silencieux / démons résiduels | Attente longue + journal détaché, `gradlew --stop`, vérifier l'APK même après interruption |
| Build Web cassé après interruption | Export interrompu en écriture | Nettoyer les artefacts et **réexporter proprement** ; vérifier magic/tailles |

## 7. Checklist export

**Avant**
- [ ] `git status` connu ; seuls des fichiers sources utiles seront modifiés.
- [ ] Alignement des versions : `project.godot` `config/version`, preset Android (`version/name`, `version/code`), preset Windows (`file_version`, `product_version`).
- [ ] `--import` à jour (nouveaux scripts/ressources, ex. JSON).

**Après (par plateforme)**
- [ ] Web : copie des JS moteur, `patch_pwa_sw.py`, contrôle magic `.wasm`/`.pck`, HTTP 200 (multi-thread).
- [ ] Windows : `FileVersion`, test de fumée moteur, zip avec `bin/` + LICENSE + NOTICE.
- [ ] Android : `aapt badging`, libs arm64, `apksigner verify`, taille/horodatage.
- [ ] Validation globale : `--headless --path . --quit` sans erreur + tests headless (`tests/*.gd`).

**Hygiène git**
- [ ] Aucun commit/push pendant l'export.
- [ ] Aucun fichier protégé indexé (`*.keystore`, `bin/*.exe|dll|pb.gz`, `dist/`, `RodChessXD2_Windows*.exe|zip`, `addons/RodChessUci/bin/`, `android/build/libs/**`, `android/build/src/main/jniLibs/**`, doublons racine `stockfish.js`/`uci_worker_bridge.js`).
- [ ] Push via `git push origin main-web:main` (voir skill `rodchess-deploiement-git-pwa`).

## 8. Pré-push vers GitHub (main-web → main)

**Rappel** : `main-web` est publiée **sous le nom `main`**. Commande unique : `git push origin main-web:main`.
**Jamais** `git push origin main-web` ; **jamais** pousser `main` ni `main-iOS`.

### Commandes de vérification (à exécuter avant tout push)

```powershell
# 1. Branche attendue + état de travail
git branch --show-current   # attendu : main-web
git status --short

# 2. Commits et fichiers qui seront publiés
git log --oneline origin/main..HEAD
git diff --name-only origin/main..HEAD

# 3. Détection de chemins protégés (doit ne rien retourner)
git diff --name-only origin/main..HEAD | Select-String -Pattern '(\.keystore$|\.exe$|\.dll$|\.so$|\.apk$|\.aab$|\.zip$|\.pb\.gz$|^bin/|^dist/|addons/RodChessUci/bin/|android/build/libs/|android/build/src/main/jniLibs/|^stockfish\.js$|^uci_worker_bridge\.js$|RodChessXD2\.(html|wasm|pck)$)'

# 4. Binaires suivis (doit être vide)
git ls-files | Select-String -Pattern '\.(keystore|exe|dll|so|apk|aab|zip|pb\.gz)$'

# 5. Plus gros blobs (repérer tout binaire lourd inattendu)
git ls-tree -r -l HEAD | Sort-Object { [int](($_ -split '\s+')[3]) } -Descending | Select-Object -First 15

# 6. Scan de secrets dans le diff à publier
git diff origin/main..HEAD | Select-String -Pattern 'keystore|password|passwd|api[_-]?key|secret|token|ghp_|sk-|BEGIN .*PRIVATE KEY'

# 7. Distant : uniquement refs/heads/main
git ls-remote origin

# 8. Chemins qui doivent être ignorés
git check-ignore -v dist/ RodChessXD2_Windows_v1.2.0.zip release.keystore bin/stockfish.exe stockfish.js uci_worker_bridge.js
```

### Checklist finale

- [ ] Branche courante = `main-web`.
- [ ] Aucun chemin protégé dans `git diff --name-only origin/main..HEAD`.
- [ ] Aucun blob lourd inattendu (plus gros blobs plausibles).
- [ ] Aucun secret dans le diff.
- [ ] Distant = `refs/heads/main` seul.
- [ ] CI présente : `.github/workflows/deploy-web.yml` (`push` sur `main` + `workflow_dispatch`).
- [ ] Puis publier : `git push origin main-web:main`.
- [ ] Surveiller les jobs `build` puis `deploy` ; approuver l'environnement `github-pages` à la 1ʳᵉ exécution.
- [ ] Valider la PWA sur `https://ehplodor.github.io/rodchessxd/`.

**Note** : ne jamais faire `git add -A` ; committer explicitement les fichiers voulus. Les artefacts ignorés (`dist/`, exe, apk, zip, keystores, `bin/`) ne doivent **jamais** apparaître dans `git diff --cached --name-only`.
