# Déploiement PWA Godot sur GitHub Pages (repo public Ehplodor/rodchessxd)

## Objectif
Publier le build **Web Godot 4.7.1** de RodChessXD (`Stockfish WASM` via `assets/web/stockfish.js` + pont `assets/web/uci_worker_bridge.js`) comme **PWA installable** sur `https://ehplodor.github.io/rodchessxd/`, derrière un workflow GitHub Actions d'export headless, **sans casser** les chaînes Windows (exe autonome `RodChessXD2_Windows.exe`) et Android (APK signé + plugin `RodChessUci`), en **purgeant** secrets et binaires volumineux de l'historique poussé.

## Décisions actées
1. **Repo** : `Ehplodor/rodchessxd`, **public**, créé **vide** via l'UI GitHub (template/README/.gitignore/license = **N** à la création ; ils viennent avec le code).
2. **Branches** : `main2` obsolète (supprimée après vérif). Commit du travail Windows en cours sur `main-iOS` → merge `--no-ff` dans `main` → création de `main-web` depuis `main`. `main-web` est **la seule branche poussée** (publiée comme `main` distante) et devient la branche de travail canonique ; `main`/`main-iOS`/`main2` restent **locales, jamais poussées, jamais re-fusionnées** (garde contenant secrets/binaires).
3. **Purge d'historique** : `git-filter-repo` **uniquement sur `main-web`**, dans un **clone temporaire à branche unique** (`--single-branch --branch main-web`), jamais sur le clone d'origine. Liste exacte des chemins purgés (tout l'historique + index) :
   - Secrets : `release.keystore`, `android/rodchess.keystore`
   - Binaires/heavy : `bin/lc0.exe`, `bin/dnnl.dll`, `bin/mimalloc-override.dll`, `bin/mimalloc-redirect.dll`, `bin/791556.pb.gz`
   - Android template/plugin : `android/build/libs/` (`*.so`, `godot-lib.template_*.aar`), `android/build/src/main/jniLibs/`, `addons/RodChessUci/bin/` (`*.aar`)
   - Doublons racine : `stockfish.js`, `uci_worker_bridge.js` (canonique : `assets/web/`)
   - Les `.exe`/`.zip` Windows et `bin/*.pb.gz` Maia sont **déjà hors index** (ignorés) → rien à purger pour eux.
   - **Les fichiers restent sur disque dans le clone d'origine** (dev machine intacte → exports locaux Windows/Android non cassés).
4. **PWA** : activée dans le preset Web existant (`progressive_web_app/enabled=true`), `display=standalone`, icônes 144/180/512 générées depuis `icon.svg`, manifest + service worker **générés par l'exporteur Godot**. Build **mono-thread** conservé (`variant/thread_support=false` ; template `web_nothreads_release` utilisé) car GitHub Pages ne peut pas envoyer COOP/COEP (`ensure_cross_origin_isolation_headers=false`).
5. **Licence** : **GPL-3.0** sur tout le dépôt (`LICENSE`) + `NOTICE.md` (composants tiers : stockfish.js GPLv3, dnnl Apache-2.0, mimalloc MIT, poids Maia — avec sources upstream). Aucune clé API en dur détectée (coach BYOK, clés saisies par l'utilisateur) ; aucun mot de passe dans les fichiers Gradle suivis (tout passe par `project.property`).
6. **itch.io** : la page présente le **Desktop Windows en téléchargement principal** ; description corrigée pour être exacte côté Windows **+ lien « Essayer en ligne » vers la PWA GitHub Pages**. Le texte PWA/web (matrice features) va dans le `README`.

## Contexte technique vérifié (lecture code/templates)
- Version : **Godot 4.7.1.stable** (templates locaux présents, dont `web_nothreads_release.zip`). App `RodChessXD` v1.1.0, GL Compatibility, viewport 450×800 portrait.
- **Web = Stockfish uniquement** : `start_engine()` → `_start_wasm_engine()` (EngineManager.gd:727,1419) ; lc0/Maia indisponibles (nets absentes du build Web, `get_lc0_download_available()` Windows-only). Sur Web, `has_engine_binary()` renvoie `true` (EngineManager.gd:471) → l'Engine Hub affiche « Stockfish (Disponible) ».
- UI Web imparfaite (constat, **non corrigée** dans ce plan) : EngineHub montre la section Maia/lc0 « placez le binaire » et les cartes `DOWNLOADABLE_ENGINES` téléchargeables dans `user://` sans effet ; ModelHub/LLM local non exécutable dans un navigateur. Le texte publié ne doit pas les promettre.
- Analyse Web : chemin asynchrone `await` déjà implémenté (`Main.gd:1230-1232`, `GameAnalyzer.start_game_analysis_async`).
- `user://` = IndexedDB sur Web (persistance réglages/parties OK). `serve_web.py` (localhost, COOP/COEP, sert la racine) reste fonctionnel : les 2 `.js` racine purgés de git restent **sur disque** pour l'usage local.
- Plugin `addons/RodChessUci/export_plugin.gd` : ne s'attache qu'à Android (`_supports_platform`) → **aucun impact** sur l'export Web CI après purge des AAR. Sur un clone public frais, un export Android nécessitera de régénérer les AAR depuis `android/plugins/uci_process` (documenté au README).

## Pré-requis utilisateur avant exécution
- **Créer le repo GitHub `Ehplodor/rodchessxd`** (public, vide : pas de template, README, .gitignore ni licence à la création) — nécessaire avant T16 **[UI]**.
- Compte GitHub authentifié localement (`gh auth status` ou Gestionnaire d'identifiants Windows) ; le premier `git push` peut demander une connexion interactive **[UI]**.
- Décision gardée hors de ce plan : générer un **nouveau keystore Android** si l'actuel a déjà signé une APK publiée (sinon on conserve la clé locale en lieu sûr).

---

## Phase 0 — Sauvegardes & commits préparatoires (branche `main-iOS`)
- [ ] **T1 Sauvegarde** : `mkdir C:\Dev\backup` ; `git bundle create C:\Dev\backup\rodchessxd-<date>.bundle --all`. Copier `release.keystore` et `android\rodchess.keystore` dans le backup (hors machine si possible). Vérifier alias/mot de passe connus (config éditeur Godot, hors repo).
- [ ] **T2 Outil purge** : vérifier `git filter-repo --version` ; sinon `python -m pip install git-filter-repo`.
- [ ] **T3 Commit du travail en cours** (modifs Windows non commitées) :
  1. Étendre `.gitignore` (ajouts en fin de fichier) :
     ```
     # Windows deliverable (local only)
     /RodChessXD2_Windows.exe
     /RodChessXD2_Windows_v*.zip
     # Engine binaries / nets (local only, purgés du public)
     /bin/*.exe
     /bin/*.dll
     /bin/*.pb.gz
     # Android secrets & template binaries
     *.keystore
     /addons/RodChessUci/bin/*.aar
     /android/build/libs/**
     /android/build/src/main/jniLibs/**
     # Racine = doublons web (canonique : assets/web/)
     /stockfish.js
     /uci_worker_bridge.js
     # Export PWA local
     /dist/
     ```
  2. `git add .gitignore export_presets.cfg src/engine/EngineManager.gd`
  3. Commit style repo (FR), ex. `feat(export): preset Windows Desktop + provisioning moteurs embarqués`.
- [ ] **T4 Ménage branches** : `git log --oneline main2 --not main` vide → `git branch -d main2`. Vérifier divergence : `git log --oneline main-iOS..main` vide (sinon résoudre avant merge). `git checkout main && git merge --no-ff main-iOS -m "merge: main-iOS dans main"`.
- [ ] **T5 Branche publique** : `git checkout -b main-web main`. Toutes les étapes suivantes se font sur `main-web`.

## Phase 1 — Configuration PWA du preset Web (commits sur `main-web`)
- [ ] **T6 Icônes PWA** : écrire `tools/render_pwa_icons.gd` (SceneTree : `Image.load_svg_from_file("res://icon.svg")` puis `resize_smooth()` et `save_png()` pour 144, 180, 512). Lancer : `<godot 4.7.1 console> --headless --path . --script res://tools/render_pwa_icons.gd` → `assets/web/icons/icon-144.png|icon-180.png|icon-512.png` (valider dimensions/taille > 0). Fallback si SVG refusé : import SVG + `get_image()`. Commit des PNG + du script.
- [ ] **T7 Preset Web → PWA** (`export_presets.cfg`, section `[preset.0.options]` **uniquement** — presets Android/iOS/Windows intacts) :
  - `progressive_web_app/enabled=true`
  - `progressive_web_app/ensure_cross_origin_isolation_headers=false`
  - `progressive_web_app/display=1`, `orientation=0`
  - `progressive_web_app/background_color=Color(0.0705882, 0.0823529, 0.109804, 1)` (aligné boot splash `#121A1C`)
  - `progressive_web_app/icon_144x144="res://assets/web/icons/icon-144.png"` (idem 180, 512)
  - `html/head_include` : `<script src=\"uci_worker_bridge.js\"></script><meta name=\"theme-color\" content=\"#121a1c\">`
  - Ne pas toucher à `variant/thread_support=false`.
- [ ] **T8 Export local de contrôle** : `--headless --path . --export-release "Web" <tmp>\index.html` puis copier `assets/web/uci_worker_bridge.js` + `assets/web/stockfish.js` à côté. **Constate et note** les artefacts PWA produits (noms exacts du manifest/service worker, icônes copiées ou inline). Vérifier que l'analyse démarre (console : `moteur Web Stockfish Wasm démarré`).

## Phase 2 — Workflow GitHub Actions (commit sur `main-web`)
- [ ] **T9 `.github/workflows/deploy-web.yml`** :
  - Déclencheurs : `push` sur `main` + `workflow_dispatch`.
  - Job `build` (ubuntu-latest) :
    1. `actions/checkout@v4`
    2. Télécharger `Godot_v4.7.1-stable_linux.x86_64.zip` + `Godot_v4.7.1-stable_export_templates.tpz` depuis les releases officielles godotengine/godot (vérifier les URLs ; sinon aligner sur la version exacte des templates locaux).
    3. Dézipper Godot ; installer les templates dans `~/.local/share/godot/export_templates/4.7.1.stable/`.
    4. `godot --headless --path . --import` puis `godot --headless --path . --export-release "Web" dist/index.html`.
    5. `cp assets/web/uci_worker_bridge.js assets/web/stockfish.js dist/`
    6. `actions/upload-pages-artifact@v3` (`path: dist`).
  - Job `deploy` : `needs: build`, `environment: github-pages` (URL = sortie `deploy-pages`), permissions `pages: write` + `id-token: write`, `actions/deploy-pages@v4`.
- [ ] **T10 Rejouer la séquence T8/T9 en local** vers `dist/` (smoke CI), y compris la copie des 2 `.js`, et lister `dist/`.

## Phase 3 — README, LICENSE, NOTICE, copie itch (commits sur `main-web`)
- [ ] **T11 `LICENSE`** : texte intégral GPL-3.0.
- [ ] **T12 `NOTICE.md`** : stockfish.js (GPLv3 + URL source upstream), uci_worker_bridge.js (projet), dnnl (Apache-2.0), mimalloc (MIT), poids Maia (licence des poids à préciser + provenance), polices Noto (OFL à confirmer).
- [ ] **T13 `README.md`** : présentation, **matrice features** (voir T18) Desktop Windows vs Web PWA, démarrage rapide (éditeur ; Web local : export + copie des 2 `.js` puis `python serve_web.py`), déploiement (ce workflow), licence, structure, notes « moteurs/secrets Android non versionnés ; builds Desktop/Android locaux ; export Android = régénérer les AAR depuis `android/plugins/uci_process` ».
- [ ] **T14 `docs/ITCH_PAGE_COPY.md`** : copie prête à coller pour la page itch **Windows d'abord** (features Desktop réelles : Stockfish/lc0/Maia/OCR/LLM local uniquement si réellement présents dans l'exe) + bloc « Essayer en ligne » avec l'URL de la PWA Pages ; **aucune** promesse Web-only.

## Phase 4 — Purge d'historique & push
- [ ] **T15 Purge (clone temporaire jetable)** — jamais sur le clone d'origine :
  1. `git clone --single-branch --branch main-web --no-local file://C:/Dev/RodChessXD C:/Users/<user>/AppData/Local/Temp/kilo/rodchessxd-public`
  2. `cd <tmp>` puis `git filter-repo --invert-paths` + un `--path` par élément de la liste des Décisions §3.
  3. Vérifications dans `<tmp>` : `git log --all --oneline -- <chaque chemin>` vide ; `git ls-files` sans `keystore`, `.so`, `.aar`, `.dll`, `.exe`, `.pb.gz` ; `git count-objects -vH` cohérent (historique allégé).
  4. Dans **l'original** : `Test-Path` sur keystores, `bin/lc0.exe`, `bin/791556.pb.gz`, `addons/RodChessUci/bin/*.aar`, `android/build/libs/**/*.so` → tous présents sur disque ; `git status` propre.
- [ ] **T16 Push** : dans `<tmp>`, `git remote set-url origin https://github.com/Ehplodor/rodchessxd.git` puis `git push origin main-web:main`. Vérifier que seule `main` distante existe (`git ls-remote --heads origin`). Le clone temporaire peut être supprimé ensuite.
- [ ] **T17 [UI]** : GitHub `Settings → Pages → Source: GitHub Actions`. Lancer le workflow (le push le déclenche, sinon `workflow_dispatch`). Noter `https://ehplodor.github.io/rodchessxd/`. La 1re exécution peut demander l'approbation de l'environnement `github-pages`.

## Phase 5 — Validation & non-régression
- [ ] **T18 Matrice features (pré-remplie, à confirmer par test)** :
  - Web/PWA : Stockfish WASM (analyse live + analyse de partie asynchrone), PGN, banque de parties & réglages persistés (IndexedDB), coach cloud BYOK (CORS Gemini/Groq **à vérifier**). **Indisponibles** : Maia/lc0, téléchargements Engine Hub (inopérants), LLM local/modèles embarqués, OCR/camera, Chess.com (CORS à vérifier). Saisir la matrice dans le `README`.
- [ ] **T19 Validation PWA locale** : servir `dist/` (`python -m http.server`, localhost) → manifest présent, service worker enregistré, **hors-ligne** (DevTools → Offline) au 2e chargement **y compris analyse moteur** (worker `stockfish.js` servi/caché), icônes, `display: standalone`, installation Chrome/Android si dispo.
- [ ] **T20 Validation PWA distante (https)** : rejouer T19 sur `ehplodor.github.io/rodchessxd/` ; `theme-color`, rafraîchissement après un 2e déploiement (mise à jour du SW), console sans erreur.
- [ ] **T21 Non-régression Desktop/Android** : présence disque intacte (T15.4), `export_presets.cfg` inchangé hors modifications actées, exports locaux inchangés ; optionnel : re-export Windows `--export-release "Windows Desktop"` vers un chemin temporaire (l'`include_filter="bin/*"` embarque toujours les fichiers disque).

## Hors périmètre
- Corrections de bugs/UI du build Web révélées par T18 (EngineHub/ModelHub sur Web, etc.) → plan séparé.
- CI Windows/Android (exports Desktop/Android locaux, secrets hors repo).
- Domaine personnalisé, stores, mise en ligne itch (contenu fourni T14, collage manuel **[UI]**).
- Réécriture d'historique des branches locales `main`/`main-iOS`/`main2`.

## Risques & parades
- **Fuite de secrets** : purge `filter-repo` en clone jetable + vérifs T15 ; ne jamais pousser d'autre branche. Si une APK signée de l'ancien keystore a déjà été publiée → régénérer le keystore avant toute release Android.
- **GPL** : dépôt entier GPL-3.0 + `NOTICE.md`. Moteurs embarqués locaux hors repo public.
- **Pages sans COI** : build mono-thread obligatoire (acté) ; ne pas réactiver `thread_support` sans hébergeur COI.
- **Noms d'artefacts PWA Godot 4.7** : constatés en T8/T10 ; le workflow pousse tout `dist/`, donc insensible aux noms ; le SW doit couvrir `stockfish.js`/`uci_worker_bridge.js` hors-ligne (validé T19 ; sinon précache ajouté en post-traitement).
- **CORS Coach/Chess.com** : mesuré en T18, consigné dans la matrice, pas promis par le texte.

## Livrables finaux
- Repo public `Ehplodor/rodchessxd`, branche `main` = `main-web` purgée ; PWA installable sur `https://ehplodor.github.io/rodchessxd/`.
- `LICENSE` (GPL-3.0), `NOTICE.md`, `README.md`, `docs/ITCH_PAGE_COPY.md`, `.github/workflows/deploy-web.yml`, `assets/web/icons/icon-{144,180,512}.png`, `tools/render_pwa_icons.gd`.
- Branches locales Desktop/Android intactes (`main`, `main-iOS` conservées, `main2` supprimée), builds Windows/Android non cassés (T21).
