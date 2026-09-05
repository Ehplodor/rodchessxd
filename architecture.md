# Architecture de RodChessXD

> Documentation technique de référence — structure, composants et flux de l'application.
> Projet : RodChessXD 1.0.0 — Application mobile multi-plateforme d'analyse échiquéenne (Stockfish + Coach IA LLM/SLM).
> Moteur : Godot 4.7.x (GDScript, 2D, rendu `gl_compatibility`).

---

## 1. Vue d'ensemble

RodChessXD est une application Godot 2D **orientée portrait** (viewport 450 × 800, orientation portrait verrouillée, stretch `canvas_items`/`expand`) qui permet d'analyser des parties d'échecs sur mobile et desktop :

- **Import de positions/parties** : capture d'écran PNG (OCR local à base de pixels, pas de réseau), texte/fichier PGN, ou parties d'un joueur **Chess.com** (API REST).
- **Analyse moteur locale** : Stockfish (UCI) exécuté en sous-processus, communication par pipe, analyse coup par coup, ACPL, précision, estimation ELO, graphe d'avantage.
- **Coach IA** : explication en langage naturel d'une position via 8 fournisseurs (OpenRouter, Groq, Gemini, DeepSeek, OpenAI, Anthropic, Ollama local, SLM local « llama-server » sidecar).
- **Persistance locale** : bibliothèque de parties + analyses + échanges coach, en JSON dans `user://`.

Plateformes cibles configurées (`export_presets.cfg`) : **Web** (`RodChessXD2.html`) et **Android** (`RodChessXD2.apk`, arm64-v8a, debug et release). Le code cible historiquement Windows en développement (binaires `.exe` embarqués — cf. §10).

---

## 2. Arborescence du projet

```
RodChessXD/
├── project.godot              # Configuration moteur (autoloads, rendu, viewport)
├── export_presets.cfg         # Présets d'export Web + Android
├── planexec.md                # Plan produit (docs)
├── architecture.md            # Ce document
├── requeteshttp.md            # Inventaire réseau & diagnostic Android
├── src/
│   ├── core/                  # Logique échiquéenne pure + état + persistance
│   │   ├── ChessPiece.gd      #   Enums/types de pièces, symboles, chemins SVG
│   │   ├── ChessMove.gd       #   Modèle d'un coup + métriques de qualité
│   │   ├── ChessGame.gd       #   Moteur de règles (FEN, PGN, SAN, légalité)
│   │   ├── GameController.gd  #   [AUTOLOAD] État de la partie courante
│   │   ├── DatabaseManager.gd #   [AUTOLOAD] Bibliothèque JSON locale
│   │   └── SettingsManager.gd #   [AUTOLOAD] Réglages persistants (user://settings.cfg)
│   ├── engine/
│   │   ├── EngineManager.gd   #   [AUTOLOAD] Cycle de vie Stockfish/UCI, téléchargements Maia
│   │   └── GameAnalyzer.gd    #   Analyse globale (ACPL, précision, ELO, stats)
│   ├── ai/
│   │   ├── AICoach.gd         #   [AUTOLOAD] Prompts + appels LLM/SLM multi-fournisseurs
│   │   ├── ModelCatalog.gd    #   [AUTOLOAD] Catalogue de modèles (+sync OpenRouter/Ollama)
│   │   ├── ModelDownloader.gd #   [AUTOLOAD] Téléchargement GGUF (Hugging Face)
│   │   └── LocalSLMManager.gd #   [AUTOLOAD] Superviseur llama-server local (127.0.0.1:8085)
│   ├── network/
│   │   └── ChessComService.gd #   Client API publique Chess.com (instancié, non-autoload)
│   ├── vision/
│   │   └── ChessOCR.gd        #   Reconnaissance échiquier image → FEN (100 % local)
│   └── ui/
│       ├── Main.gd / Main.tscn#   Scène principale + contrôleur d'interface
│       └── components/        #   Widgets 2D + fenêtres modales (voir §6)
├── assets/
│   ├── pieces/                # SVG de pièces (générés par tools/generate_pieces.py)
│   └── sounds/                # WAV coup/capture/échec (tools/generate_sounds.py)
├── bin/stockfish.exe          # Binaire moteur Windows embarqué (ressource res://bin/)
├── tools/                     # Scripts dev (génération assets, serveur web local)
├── tests/                     # Tests GDScript (test_*.gd)
├── android/build/             # Template de build Android personnalisé (Gradle) extrait
├── serve_web.py / Lancer_Web.bat  # Serveur local de la sortie Web
└── *.apk / *.wasm / *.pck     # Artefacts d'export
```

---

## 3. Couches & singletons (autoloads)

Ordre de chargement défini dans `project.godot` → `[autoload]` :

| # | Singleton | Fichier | Rôle principal |
|---|-----------|---------|----------------|
| 1 | `SettingsManager` | src/core/SettingsManager.gd | Réglages persistants (`user://settings.cfg`), clés API, moteur, thème |
| 2 | `DatabaseManager` | src/core/DatabaseManager.gd | Persistance JSON des parties/analyses/coach (`user://library/`) |
| 3 | `ModelCatalog` | src/ai/ModelCatalog.gd | Catalogue de modèles IA (curated + sync web + détection Ollama) |
| 4 | `ModelDownloader` | src/ai/ModelDownloader.gd | Téléchargement GGUF streamé sur disque (`user://models/`) |
| 5 | `LocalSLMManager` | src/ai/LocalSLMManager.gd | Lancement/supervision d'un `llama-server.exe` sur `127.0.0.1:8085` |
| 6 | `GameController` | src/core/GameController.gd | Partie active, navigation, interaction, synchronisation UI |
| 7 | `EngineManager` | src/engine/EngineManager.gd | Sous-processus Stockfish (UCI), évaluations, liste des moteurs téléchargeables |
| 8 | `AICoach` | src/ai/AICoach.gd | Orchestration du coach : prompts, routage fournisseur, archivage |

`ChessComService` (src/network) **n'est pas un autoload** : il est instancié par la modale `ChessComImportModal`. Les classes utilitaires `ChessPiece`, `ChessMove`, `ChessGame`, `ChessOCR`, `GameAnalyzer` sont des `RefCounted` (aucun nœud de scène).

### Couches logicielles

```
┌────────────────────────────── COUCHE UI (src/ui) ──────────────────────────────┐
│  Main.tscn : TopBar · CenterArea (EvalBar · ChessBoard2D) · NavRow ·           │
│              BottomTabs [Bilan: Stats/AdvantageGraph2D/MoveList2D | Coach:     │
│              CoachPanel2D]  +  modales Window (OCR, PGN, Chess.com, Engine     │
│              Hub, Library, Settings, Model Hub)                                │
└──────────────┬──────────────────────────────┬──────────────────────────────────┘
               │ signaux                     │ signaux
┌──────────────▼──────────────┐ ┌────────────▼───────────────────┐
│  GameController (état)      │ │  AICoach / ModelCatalog        │
│  └─ ChessGame (règles)      │ │  └─ HTTPRequest → fournisseurs │
└──────────────┬──────────────┘ └────────────┬───────────────────┘
               │ position FEN                  │ contextes
┌──────────────▼──────────────┐ ┌────────────▼───────────────────┐
│  EngineManager ──pipe──►    │ │  ModelDownloader /             │
│  stockfish.exe (UCI/thread) │ │  LocalSLMManager (llama-server)│
│  └─ GameAnalyzer            │ └────────────────────────────────┘
└──────────────┬──────────────┘
               │ fichiers JSON
┌──────────────▼──────────────┐
│  DatabaseManager / Settings │   user://library, settings.cfg,
│  (persistance locale)       │   user://models, user://engines
└─────────────────────────────┘
```

---

## 4. Cœur de jeu (`src/core`)

### ChessPiece.gd
Définit les constantes (`PieceColor` WHITE/BLACK/NONE, `Type` PAWN…KING), les symboles algébriques, et fournit le chemin d'asset SVG (`res://assets/pieces/…`).

### ChessMove.gd
Modèle d'un coup : cases source/cible (index 0–63), pièce, capture, promotion, roque, en passant, échec/mat, SAN/UCI — enrichi après analyse par `quality` (enum `Quality` : BEST…BLUNDER/MISS) et `centipawn_loss`.

### ChessGame.gd
Moteur de règles complet et autonome (~870 lignes) :
- Plateau 64 cases (0 = a1, 63 = h8), trait, droits de roque, en passant, horloges ;
- `load_fen` / `get_fen`, `make_move`, légalité par case, détection échec/mat/pat, navigate dans `move_history` via états restaurés ;
- PGN : en-têtes, SAN, annotations, variantes, export (`export_pgn`) ;
- Décodage **en langage naturel** d'un coup : `describe_move_from_fen`, `format_pv_natural_text` (réutilisé par les prompts du coach).

### GameController.gd (autoload)
Singleton d'état central : `game` (instance `ChessGame`), `current_ply_index`, mode de jeu (`ANALYSIS/FREE_PLAY/PLAY_VS_ENGINE`), `current_game_id`. Points clés :
- **Signaux UI** : `position_changed`, `move_made`, `square_selected`, `play_sound_requested`, etc. — l'UI se branche dessus (`Main.gd`, `ChessBoard2D`…).
- **Évaluation automatique** : chaque navigation/coup déclenche `EngineManager.evaluate_position(fen)`.
- **Sauvegarde automatique** : chaque import/partie active est archivée via `DatabaseManager` (`get_or_create_game_id`).

### DatabaseManager.gd (autoload)
Persistance 100 % locale en JSON :
- `user://library/games/<id>.json` (1 fichier par partie) + index `games_index.json` ;
- API : `save_game`, `get_game`, `list_games(query, source)`, `delete_game`, `add_engine_analysis`, `add_coach_analysis` (accumulation multi-analyses), `record_pgn_game`, `record_chesscom_game`, `record_active_game` ;
- Sources typées : `manual_play`, `pgn_import`, `chess_com`, `fen_import`, `ocr_scan` (selon appelant).

### SettingsManager.gd (autoload)
`ConfigFile` dans `user://settings.cfg`, dictionnaire de défauts : moteur (threads/hash/depth/multipv/chemin), thème/son, fournisseur IA (`ai_provider`, `ai_free_service`, `ai_api_service`, `active_model_id`), clés API (`api_key_openai/gemini/anthropic/groq/deepseek/openrouter`), `local_slm_url` (Ollama), personnalité coach, flip.

---

## 5. Moteur & analyse (`src/engine`)

### EngineManager.gd (autoload)
- **Sous-processus Stockfish** : `OS.execute_with_pipe(exe, [])` → flux `stdio` verrouillé par mutex ; lecteur UCI dans un `Thread` dédié ; parsing de `info … score cp/mate … pv …` (normalisation du score côté Blancs, gestion multipv) et de `bestmove`.
- **Chemin du binaire** : réglage `engine_path` → `user://engines/stockfish.exe` → `res://bin/stockfish.exe` (binaire Windows embarqué) → chemins dev.
- **API** : `start_engine`, `stop_engine`, `evaluate_position(fen, depth)` (async), `evaluate_position_sync(fen, depth, timeout)` (utilisé par `GameAnalyzer`), `send_command`.
- **Catalogue de téléchargements** `DOWNLOADABLE_ENGINES` : 3 réseaux neuronaux Maia (1100/1500/1900) hébergés sur GitHub (téléchargés par `EngineHubModal`, §6).

### GameAnalyzer.gd (`RefCounted`)
Analyse de partie complète, exécutée dans un `Thread` créé par `Main.gd` :
- Pour chaque demi-coup : évaluation synchronisée, perte en centipions, classification de qualité, compteurs ;
- Sortie : courbe `evaluations`, ACPL Blancs/Noirs, précisions (%), **estimation ELO**, stats (brillants/gaffes…) et rapport consolidé `analysis_finished(report)`.

---

## 6. Interface (`src/ui`)

### Main.tscn / Main.gd
Scène principale (scène de démarrage `run/main_scene`). Arbre :
`Main (Control)` → `Background`, `VBox` → `TopBar` (titre + badge d'éval + boutons PNG/PGN/Chess.com/flip/⚡/📚/⚙️), `CenterArea` (`EvalBar2D`, `ChessBoard2D`), `NavRow` (⏮ ◀ ▶ ⏭ + « 🔍 Analyser Partie »), `BottomTabs` (onglet *Bilan* : StatsLabel, `AdvantageGraph2D`, `MoveList2D` ; onglet *Coach* : `CoachPanel2D`), `Sounds` (3 `AudioStreamPlayer`).

`Main.gd` : thème sombre, gestion d'une **modale unique à la fois** (`_open_modal` → `Window`), déclenchement de l'analyse de partie dans un thread (`_on_btn_analyze_game_pressed`), réception du rapport (`_on_analysis_finished`) → graphe, stats, archivage `DatabaseManager.add_engine_analysis`, bascule d'onglet automatique.

### Widgets 2D (src/ui/components)
| Composant | Type | Rôle |
|---|---|---|
| `ChessBoard2D` | Control | Plateau interactif tactile : cases, pièces SVG, animations fluides, glissement physique, thèmes, flip |
| `EvalBar2D` | Control | Barre d'évaluation verticale animée (cp/mat) |
| `AdvantageGraph2D` | Control | Courbe d'avantage interactive (zoom, HUD, analyse stockée par jeu) |
| `MoveList2D` | ScrollContainer | Feuille de coups avec pastilles de qualité et navigation par clic |
| `CoachPanel2D` | PanelContainer | Chat coach : perspective, question libre, badge modèle ouvrant le Model Hub, historique, erreurs |

### Fenêtres modales (Window, créées à la volée)
| Modale | Rôle | Réseau ? |
|---|---|---|
| `OCREditorModal` | Import PNG → OCR `ChessOCR`, correction manuelle (palette, trait), validation FEN | non |
| `PGNModal` | Import/export PGN (presse-papiers, fichier) | non |
| `ChessComImportModal` | Saisie pseudo → `ChessComService` → liste filtrable (bullet/blitz/rapide/daily) → enregistrement bibliothèque | **oui** |
| `EngineHubModal` | Cartes moteurs Maia, **téléchargement** direct vers `user://engines/` | **oui** |
| `ModelHubModal` | Hub de modèles IA : onglets gratuit/API/local, **sync catalogue OpenRouter**, **détection Ollama**, **installation GGUF**, clés API | **oui** |
| `LibraryModal` | Bibliothèque locale : recherche, filtres par source, chargement, export | non |
| `SettingsModal` | Paramètres moteur/son/coach, clés IA | non (champs) |

---

## 7. Intelligence artificielle (`src/ai`)

### AICoach.gd (autoload) — le « coach »
- `build_prompt_data(fen, last_move_san, eval_cp, best_move, pv, question, extra)` : fiche technique (phase, matériel, qualité du coup, PV décodé en langage naturel), instructions système par perspective (Blancs/Noirs/neutre) et personnalité (`mentor`, `blunder_hunter`, `kids_simple`), règles anti-hallucination (jamais contredire Stockfish), format Markdown imposé.
- `ask_coach(...)` : lit `active_model_id` dans les réglages, cherche le modèle dans `ModelCatalog`, puis route vers le fournisseur détecté (`provider`) :
  - `openrouter` (défaut), `groq`, `gemini`, `deepseek`, `openai`, `anthropic` → **HTTP POST HTTPS** (détails : `requeteshttp.md`) ;
  - `ollama` → POST `http://127.0.0.1:11434/api/generate` ;
  - `native_slm` → vérifie modèle GGUF installé (`ModelDownloader`), démarre le serveur (`LocalSLMManager`), POST sur `http://127.0.0.1:8085/v1/chat/completions`.
- Réception : parsing par format (OpenAI-compatible `choices`, Gemini `candidates`, Anthropic `content`, Ollama `response`), gestion 401/403/429/autres avec messages pédagogiques ; compteur de session, estimation du coût USD via `ModelCatalog.get_cost_estimate` ; **archivage automatique** `DatabaseManager.add_coach_analysis`.
- Secours hors-ligne `_fallback_offline_explanation` : si aucune clé n'est configurée, réponse locale exploitant uniquement les données Stockfish.

### ModelCatalog.gd (autoload)
- Catalogue « curaté » embarqué (modèles gratuits/payants Sept. 2026) fusionné avec une **sync web** (`fetch_online_catalog` → `GET https://openrouter.ai/api/v1/models`, filtrage par pertinence échecs) et les modèles détectés dans **Ollama** (`GET http://127.0.0.1:11434/api/tags`) ;
- Cache local `user://ai_models_catalog.json` (schéma versionné) ;
- Estimation des coûts (`price_in/out_per_1m`, tokens estimés 500 in/300 out par analyse) ;
- Accès : `find_model_by_id`, `get_models_by_modality`.

### ModelDownloader.gd (autoload)
Téléchargement de modèles SLM **GGUF** (SmolLM2 360M, Qwen 2.5 0.5B, SmolLM2 1.7B) depuis Hugging Face avec `HTTPRequest.use_threads = true` et `download_file` (écriture directe sur disque `user://models/`, pas de buffer mémoire), progression/surveillance du débit dans `_process`, annulation propre, suppression. Vérifie la taille connue pour la jauge.

### LocalSLMManager.gd (autoload)
Cycle de vie d'un « sidecar » d'inférence locale (OpenAI-compatible, type llama.cpp `llama-server`) :
- `start_server_for_model(model_id, port=8085)` : localise `llama-server.exe` (réglage → `user://bin` → `res://bin` → chemins dev), lance `OS.create_process` avec `-m <gguf> --port 8085 -c 2048 -n 512 -t 4 --nobrowser` ;
- **Sondage de santé** : `GET http://127.0.0.1:8085/health` (HTTPRequest, timeout 2 s, jusqu'à 20 tentatives à 1 s) ;
- `stop_server` (kill) sur fermeture d'application ; URL d'API exposée `http://127.0.0.1:<port>/v1/chat/completions`.

---

## 8. Vision (`src/vision/ChessOCR.gd`)

Reconnaissance **déterministe sans réseau ni modèle** : détection du rectangle 8×8 (heuristiques carré centré portrait/paysage), analyse de chaque case par échantillonnage de pixels (luminance de fond, variance centrale, répartition verticale des pixels actifs → silhouette → type de pièce), sortie FEN. Complété dans `OCREditorModal` par une correction manuelle grille + palette.

---

## 9. Réseau (`src/network`) — renvoi

Toutes les sorties HTTP passent par des nœuds `HTTPRequest` :
- `ChessComService.gd` : GET `https://api.chess.com/pub/player/{pseudo}/games/archives` puis GET de l'archive mensuelle la plus récente ; parse PGN/métadonnées ; émet `games_fetched` / `fetch_error`.
- Autres consommateurs réseau : `AICoach`, `ModelCatalog`, `ModelDownloader`, `LocalSLMManager`, `EngineHubModal` (téléchargements moteurs).

**L'inventaire exhaustif des requêtes (URLs, méthodes, en-têtes, déclencheurs) et le diagnostic du problème réseau Android sont documentés dans [`requeteshttp.md`](requeteshttp.md).**

---

## 10. Particularités & limites transverses

1. **Binaires `.exe` Windows dans un projet mobile** : `res://bin/stockfish.exe` (utilisé par `EngineManager`) et le principe `llama-server.exe` de `LocalSLMManager` supposent un sous-processus exécutable. Sur **Android**, aucun `.so` natif n'est embarqué et `OS.execute_with_pipe`/`OS.create_process` ne peuvent pas exécuter ces binaires : les fonctionnalités d'analyse moteur et de SLM local *packagé* sont donc inopérantes sur Android en l'état (le plan produit `planexec.md` prévoyait une intégration GDExtension/`.so` pour le mobile — non implémentée). L'OCR (pur GDScript) reste fonctionnel partout.
2. **`user://`** est le seul répertoire persistant multi-plateforme (bibliothèque, réglages, modèles, moteurs téléchargés). Sur Android, tout `FileAccess` y est autorisé sans permission.
3. **Le réseau mobile** dépend exclusivement du manifeste Android : aucune permission n'était déclarée dans l'APK exporté → échec immédiat de **toutes** les requêtes HTTPS comme HTTP (voir `requeteshttp.md`, cause n°1, confirmée par `aapt dump permissions`).
4. **Flux web (export HTML)** : fonctionne avec CORS côté fournisseurs (OpenRouter l'autorise, etc.) ; les flux `127.0.0.1` sont sans objet côté navigateur.
5. **Tests** : `tests/test_*.gd` (moteur de règles, OCR, coach/prompts, catalogue/téléchargement, modales, animations…) exécutables par le harnais GDScript de Godot ; aucun test réseau en ligne (mocks/fixtures uniquement).
6. **Outils de développement** : `tools/generate_pieces.py` / `generate_sounds.py` régénèrent les assets ; `serve_web.py` + `Lancer_Web.bat` servent la sortie Web en local pour les tests navigateur.

---

## 11. Démarrage & cycle de vie

1. Godot 4.7.x charge `res://src/ui/Main.tscn` → l'arbre racine instancie d'abord les 8 autoloads (ordre du tableau §3) : réglages, base de données, catalogue modèles, téléchargements, superviseur SLM, contrôleur de partie, gestionnaire de moteur (**démarre Stockfish en différé** via `call_deferred("start_engine")`), coach IA.
2. `Main._ready()` : câble les signaux (position → graphique ; éval moteur → badge ; sons), applique le thème, lance l'évaluation initiale de la position de départ.
3. Interactions utilisateur : jeu libre/import → `GameController` → évaluation Stockfish continue ; « Analyser Partie » → `GameAnalyzer` (thread) ; onglet Coach → `AICoach.ask_coach` → réponse affichée et archivée.
4. Sortie : `LocalSLMManager` tue son serveur (`NOTIFICATION_WM_CLOSE_REQUEST`), `EngineManager` envoie `quit` au moteur.

*Voir `requeteshttp.md` pour le détail complet du sous-système réseau et de ses prérequis d'export Android.*
