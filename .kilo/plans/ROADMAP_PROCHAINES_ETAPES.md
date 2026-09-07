# RodChessXD — Prochaines étapes : UX, Coach IA, données (plan v3)

> Plan à destination des prochaines personnes sur RodChessXD. v3 : spécifications
> câblées à l'état réel du code (signaux, formats, composants). Rien n'est implémenté.
>
> Contexte : Godot 4.7.1, gl_compatibility, viewport 450x800, persistance JSON
> (`user://library/games_index.json` + 1 fichier JSON par partie), autoloads
> (SettingsManager, GameController, EngineManager, AICoach, DatabaseManager…),
> plugins Android v2 (modèle `RodChessUci`).

---

## Annexe A — État câblé vérifié (à conserver à jour)

### Signaux GameController & abonnés
- `position_changed` → `Main._on_game_position_changed` (rafraîchit le graphe via
  `get_game().engine_analyses`), `MoveList2D._refresh_moves`, `ChessBoard2D._on_position_changed`.
- `move_navigated(ply)` → `ChessBoard2D._on_move_navigated` (anime ±1, reset sinon),
  `AdvantageGraph2D._on_move_navigated`, `MoveList2D._on_move_navigated` (refresh).
- `game_reset` → `ChessBoard2D._on_game_reset`.

### Navigation
- `GameController.navigate_to_ply()` (GameController.gd:161) : `restore_state()` puis
  émet `move_navigated` **et** `position_changed`, puis relance l'évaluation moteur.
- Boutons ⏮ ◀ ▶ ⏭ → `Main` (lignes 217-227) → `go_*`.
- `AdvantageGraph2D` : signaux `move_scrubbed(ply)` + navigation directe au drag
  (ligne 268) ; `_scrub_to_pos` → ply cible.
- `ChessBoard2D` possède déjà : `_animate_navigation_forward/backward`,
  `_animate_castling_rook`, FX capture, `_draw_modern_move_arrow`, gestion
  `active_tweens`/ghosts. Le bug "téléportation" : après animation ±1,
  `_on_position_changed` (ligne ~896) appelle `reset_board_visuals()` et écrase le
  tween.

### Liste des coups (`MoveList2D`, 92 lignes)
- Générée depuis `move_history` ; chaque ligne = SAN + badge
  `ChessMove.quality_to_symbol/color` (déjà coloré si `m.quality != NONE`) ; ply
  courant surligné ; clic → `navigate_to_ply` ; auto-scroll (`ensure_control_visible`).
- La qualité existe sur `ChessMove` (jeu/entraînement) mais **pas pour les parties
  importées** tant que l'analyse moteur n'est pas appliquée.

### Données (DatabaseManager)
- Fichier partie : `{id, meta…, engine_analyses[], coach_analyses[], …}` ;
  `add_engine_analysis(game_id, analysis_data)` / `add_coach_analysis(...)` ;
  `record_chesscom_game(game_info)` (source "chesscom") ; `record_pgn_game` ;
  `list_games(search, filter_source)` ; index JSON trié par date.
- `ChessComService.fetch_player_games` : **dernier mois seulement**, re-téléchargement
  complet, pas de pagination multi-mois, déduplication dépendante de
  `record_chesscom_game` (à vérifier : pas de clé `url` unique aujourd'hui).

### Coach
- `CoachPanel2D` : perspectives `white/black/neutral` ; quick chips existants (lignes
  167-172) : "Pourquoi ce coup ?", "Quel est mon plan ?", "Menaces contre moi ?",
  "Réfutation tactique", "Sécurité de mon Roi", "Explique simplement".
- `AICoach` : `build_prompt_data` (position/éval/PV/question/perspective),
  providers : local (Ollama + SLM natif), Groq, Gemini, OpenRouter, DeepSeek, OpenAI,
  Anthropic ; clés API dans `SettingsModal` ; coûts dans `ModelCatalog`.
- `Main`/`ChessBoard2D` : évaluation en direct du moteur sur la position affichée.

---

## Jalon M1 — Ergonomie & accessibilité (P0)

Règles : cible ≥ 44 px ; boutons principaux ≥ 56-70 px (48-56 dp à ~1,25 px/dp,
à confirmer sur appareil réel) ; texte ≥ 14 (corps) / ≥ 16 (boutons) ; safe areas.

1. `src/ui/theme/` design tokens (tailles, couleurs, StyleBox, hauteurs) ; audit des
   tailles en dur : `Main` (barre haute, boutons nav, onglets bas), tous les `*Modal`,
   `CoachPanel2D`, `MoveList2D`, `AdvantageGraph2D`, commandes sous plateau.
2. Safe areas : `DisplayServer.get_display_cutouts()` ; barre haute ≥ 56 px, marges.
3. Contraste AA, thème contraste élevé, autowrap, ordre pouce.
4. Acceptance : parcours complet sans à-côté ; test petit/grand écran ; scaling
   système 1.25x ; rien sous encoche/barre de gestes.

Checklist : [ ] tokens créés et appliqués [ ] barre haute refaite [ ] audit modals
[ ] test 2 appareils [ ] inventaire des tailles en dur terminé.

---

## Jalon M2 — Navigation temporelle fluide (P0/P1)

Cause racine confirmée (Annexe A) : `_on_position_changed` écrase l'animation ±1.

Correctif minimal recommandé (ne pas supprimer `position_changed`, Main en dépend
pour le graphe) :
1. `ChessBoard2D` : ajouter `var _nav_anim_active := false` ; dans
   `_on_move_navigated`, cas ±1 → `_nav_anim_active = true` avant l'animation ;
   le lever dans le `tween_callback` terminal des deux animations (+ garde de
   sécurité : timer 500 ms en cas d'interruption).
2. `_on_position_changed()` : `if _nav_anim_active: return` (le rendu final est déjà
   posé par l'animation).
3. Vérifier le cas "flip board" pendant une animation (annuler proprement).
4. Graphe en drag : throttler (~80-100 ms) + mode "instantané" pendant le drag avec
   marqueur vertical du ply ; au relâchement, un seul `navigate_to_ply` final (→
   animation ±1 si adjacent).
5. Contexte visuel : flèche du dernier coup (déjà dessinée) maintenue après la
   navigation ; libellé "coup N … SAN (+0,42)" (nouveau Label, au-dessus du graphe) ;
   auto-scroll MoveList conservé.
6. Acceptance : ◀ ▶ fluides sans flash ; drag précis ; 10 plis aller-retour sans
   fantôme ni erreur ; double appel d'évaluation moteur évité si possible (déjà
   déclenché par navigate — vérifier qu'il n'y en a pas deux via `position_changed`).

Checklist : [ ] flag d'animation board [ ] lever dans callbacks/timer [ ] flip sûr
[ ] drag throttle + marqueur [ ] libellé ply [ ] tests manuels & scène de test.

---

## Jalon M3 — Coups groupés par qualité sous le graphe (P0/P1)

Base : `MoveList2D` (badges déjà gérés via `ChessMove.quality_to_*`) ; évaluations
par ply à venir des analyses moteur archivées (`engine_analyses[]`).

1. Créer `MoveQualityService` (class_name) :
   - **réutiliser la taxonomie existante** `ChessMove.Quality` et les seuils de
     `GameAnalyzer._classify_move` (≤15 EXCELLENT, ≤40 GOOD, ≤90 INACCURACY,
     ≤200 MISTAKE, >200 BLUNDER ; #1 → BRILLIANT/BEST) — ne pas créer d'échelle
     parallèle (cf. Annexe B) ;
   - entrée : `move_evaluations` du rapport (`{ply, san, uci, score_cp, loss_cp,
     quality, best_move, fen}`) ou directement les `ChessMove` analysés (GameAnalyzer
     remplit déjà `move.quality`, `move.centipawn_loss`, `move.eval_*`,
     `move.best_move_uci` — GameAnalyzer.gd:107-112) ;
   - API : `apply_to_moves`, `group_by_quality`, `classify` (cf. Annexe C).
2. Rafraîchir `MoveList2D` en fin d'analyse : elle ne réagit qu'à
   `position_changed`/`move_navigated` → exposer `MoveList2D.refresh()` et l'appeler
   depuis `Main._on_analysis_finished` (ou connecter MoveList à l'analyzer). Les
   badges/couleurs sont déjà rendus via `ChessMove.quality_to_symbol/color` ;
   ajouter ensuite la perte cp + mini-barre + filtres.
3. Étendre `MoveList2D` : colonne perte cp + mini-barre, filtres
   (Tout / ?? / ? / ?! / ★+!!+! / ✓), ligne active + auto-scroll (existant), clic →
   navigate (existant) ; bandeau de stats par camp réutilisant `white_stats`/
   `black_stats` du rapport.
4. UI : panneau sous le graphe, repliable ; garder plateau dominant.
5. Acceptance : cohérence avec le coach (même taxonomie) ; filtres instantanés ;
   200 coups fluides (recycler les lignes si besoin) ; clic → plateau animé (M2).

Checklist : [ ] inventaire format engine_analyses [ ] service + seuils partagés
[ ] remplissage post-analyse [ ] UI badges/barres/filtres [ ] perf 200 coups.

---

## Jalon M4 — Lecture vocale (TTS) du coach (P1)

1. Plugin v2 `RodTts` (copier `RodChessUci`) : `speak(text)`, `stop()`, `setRate`,
   `setPitch`, `setLanguage`, `isAvailable()` ; signaux `tts_started/done/error` sur
   thread hôte.
2. `TtsSpeaker` (autoload) : file d'attente, interruption, réglages
   (`tts_enabled/rate/pitch/lang`), bouton 🔊 par message + lecture auto optionnelle,
   surbrillance phrase.
3. Normalisation FR avant lecture : SAN→phrases (petit/grand roque, "prend",
   "échec", "échec et mat", promotion, C/F/T/D/R), cases en toutes lettres
   ("f sept"), scores ("+0,42" → "avantage de quarante-deux centièmes", option),
   strip markdown/BBcode.
4. Desktop : bouton désactivé (ou fallback système) ; jamais de lecture auto des
   erreurs.
5. Acceptance : lecture FR correcte ; interruption immédiate ; aucune latence UI.

Checklist : [ ] plugin RodTts + AAR [ ] autoload/file [ ] normalisation FR
[ ] intégration CoachPanel [ ] réglages [ ] test interruption.

---

## Jalon M5 — Coach IA enrichi & protégé (P1)

### Prompts (ajouts aux 6 chips existants)
"💭 Et si j'avais joué X ?", "📚 Ouverture : idées et pièges", "🏁 Fin de partie",
"🎓 Adapte à mon niveau", "🔍 Analyse poussée de la partie (globale)".

### Profils
Débutant/Intermédiaire/Expert/GM (SettingsManager `coach_profile`) → variante du
system prompt (longueur, vocabulaire, notation longue pour Expert/GM). Les
perspectives Blanc/Noir/Neutre existent déjà.

### Niveaux de réflexion
Rapide/Standard/Approfondi → profondeur SF (8/16/24) + budget tokens LLM ; global +
option par question ; confirmation + coût avant Approfondi/Global.

### Analyse globale
a) évaluer tous les plis en local (GameAnalyzer, arrière-plan, progress déjà
   existants) ; b) construire résumé (erreurs majeures, score par phase, meilleur
   coup) ; c) LLM sur le résumé ; d) rendu par phases + erreurs cliquables (→ ply).

### Anti-ban (couche `RateLimiter`)
- Token bucket global + par provider ; valeurs par modèle ajoutées au catalogue
  (`rpm`, `tpm`) avec limites par défaut à confirmer : Groq ~30 RPM, OpenAI/Anthropic
  par TPM de clé, Gemini par tiers, OpenRouter dépend de la clé, DeepSeek à
  confirmer, local = illimité.
- Délai min entre requêtes ; retry backoff+jitter sur 429/5xx ; fallback provider
  (ordre configurable) ; cache JSON par hash(prompt+modèle) dans
  `user://library/cache/` (TTL 7 j, taille plafonnée) ; SLM local par défaut.

### Acceptance
10 questions identiques → 1 appel réseau ; 429 simulé → fallback ou message ; analyse
globale 60 coups < 2 min sur milieu de gamme ; cohérence Coach/panneau coups.

Checklist : [ ] RateLimiter [ ] limites catalogue [ ] cache [ ] fallback ordonné
[ ] profils [ ] niveau SF [ ] analyse globale [ ] chips + prompts [ ] tests 429.

---

## Jalon M6 — Données : synchronisation & imports (P1/P2)

### cible chess.com
1. `ChessComService` : `fetch_archives(username)` puis itération **mois par mois** du
   dernier mois synchronisé (fichier `user://library/chesscom_meta.json` :
   `{username: {last_synced_month: "2026-08", last_sync_at: …}}`) au mois courant ;
   parser l'URL d'archive (`…/games/2026/09`) ; 1 requête à la fois, ≥ 1 s entre
   archives, User-Agent, backoff 429/5xx.
2. `DatabaseManager` : clé de déduplication déterministe pour les parties chess.com
   (champ `source_key = url`) : `record_chesscom_game` doit rechercher par `url`
   dans l'index et **mettre à jour** au lieu d'ajouter ; idem PGN via hash du PGN si
   nécessaire.
3. UI (`ChessComImportModal`) : états (delta/tout recharger), progression mois par
   mois, résumé "X nouvelles • M mois • il y a Y".

### Autres sources (P2)
Lichess (`/api/games/user/{username}`), PGN fichier/presse-papiers (existant à
étendre), Lichess Explorer (ouvertures), puzzles, stats joueur.

### Acceptance
2 synchronisations → 0 doublon, 0 re-téléchargement des mois présents ; coupure
réseau → reprise au bon mois ; 200+ parties fluides.

Checklist : [ ] meta par pseudo [ ] itération mois [ ] upsert par url
[ ] boutons delta/tout [ ] UI progression [ ] tests doublons/reprise.

---

## Jalon M7 — Stockfish ELO & entraînement adaptatif (P2)

1. `EngineManager` : appliquer `setoption name UCI_LimitStrength value true` +
   `UCI_Elo value N` (1320-3190) quand le profil "entraînement" est actif
   (`engine_training_elo`), sinon force max ; clamps et note : SF ne descend pas
   sous 1320 → compléter avec `Skill Level` bas si nécessaire (à valider).
2. Estimation du niveau joueur : performance rating
   `PR = moy(ratings adverses) + 400×(victoires−défaites)/parties` (≥ 5 parties
   chess.com importées, ratings déjà stockés) → ELO moteur proposé = PR ± 100.
3. Entraînement : liste des ply marqués `?/??` (M3) d'une partie choisie →
   "que jouez-vous ici ?" ; suivi hebdo (erreurs par phase) ; explorer d'ouvertures
   optionnel (M6).
4. Acceptance : ELO effectif vérifiable en contrôle ; proposition plausible après
   10 parties ; analyse inchangée en mode normal.

---

## Jalon M8 — Beta-test & observabilité (P0 dès diffusion)

1. Écran "À propos" : versionName/versionCode, ABI, modèle, id de session ; bouton
   **"Exporter les logs"** (écrire `user://logs/rodchess_AAAA-MM-JJ_HH-MM.log`
   rotation 5 fichiers ; inclure version, device, lignes EngineManager/godot, erreurs
   récentes) puis partage via intent Android (plugin v2 "share" simple) — utilisable
   sans adb.
2. Distribution : Google Play internal testing ou APK signé ; versionCode croissant.
3. Feedback structuré : formulaire intégré (note/texte/capture) ou canal unique avec
   modèle (version, appareil, action, attendu/constaté).
4. Matrice testeurs ≥ 5 (petit écran bas de gamme, grand écran, Android récent,
   joueur faible/fort, non-technicien), 1-2 semaines ; branche `beta` + hotfix P0 ;
   journal des changements dans l'app.

---

## Ordre, estimations & risques

| Jalon | Thème | Effort | Dépend de |
|---|---|---|---|
| M1 | Ergonomie/accessibilité | M | — |
| M2 | Navigation fluide | S | — |
| M3 | Coups par qualité | M | M2 |
| M4 | TTS coach | M | pattern plugin |
| M5 | Coach enrichi + anti-ban | L | M3 |
| M6 | Sync chess.com + sources | M | — |
| M7 | ELO/entraînement | L | M3+M6 |
| M8 | Beta/observabilité | S | M1 |

Recommandé : M1+M2+M8 avant diffusion large ; M3+M4 ensuite ; M5+M6 en parallèle ;
M7 exploratoire.

Risques :
- Perf JSON : `games_index.json` réécrit en entier à chaque sauvegarde (O(n)) —
  acceptable < 500 parties, sinon dirty-flag/compaction ; fichiers par partie non
  indexés → penser à un index dérivé par source/mois si besoin (M6).
- TTS : voix FR hors-ligne variables selon l'appareil (M4).
- Échelle de qualité : à valider avec un joueur fort (M3).
- Drag du graphe : flux d'événements important → throttle obligatoire (M2).
- Profondeurs SF et budget temps de l'analyse globale : mesurer sur appareil cible
  (M5/M7).
- Limites RPM/TPM réelles des providers : à confirmer avant mise en prod (M5).

## Questions ouvertes — RÉSOLUES (v6)
Chaque question a reçu une décision ; détails dans "Décisions v6" ci-dessous.
1. Tailles cibles exactes → référentiel 360 dp + tokens (décision D1).
2. `position_changed` pendant animation → garder l'émission + flag board (D2).
3. Seuils qualité & ELO < 1320 → seuils existants partagés ; ELO via UCI_Elo ≥ 1320,
   Skill Level en dessous, à calibrer (D3).
4. ToS/cadence & limites RPM → valeurs conservatrices par défaut, configurables (D4).
5. Canal beta & format des logs → canal unique + spec logs/export (D5).
6. Contenu `stats_label` & câblage MoveList ↔ fin d'analyse → décision D6.

---

## Annexe B — Formats & taxonomie vérifiés (v4)

### Report GameAnalyzer (`GameAnalyzer._build_final_report`, ligne ~339)
Clés du rapport : `white_acpl`, `black_acpl`, `white_accuracy`, `black_accuracy`,
`white_estimated_elo`, `black_estimated_elo`, `white_stats`, `black_stats`,
`evaluations` (= `move_evaluations`, un dictionnaire par ply). Ces rapports sont
stockés dans `engine_analyses[]` (via `DatabaseManager.add_engine_analysis`, qui
ajoute `id/timestamp/date_str`) et relus par le graphe (champs `engine_name`,
`depth`, `evaluations`, accuracies, elos estimés).

Formats confirmés (v5, GameAnalyzer.gd:107-132, AdvantageGraph2D.gd:161-165) :
- un item de `move_evaluations` =
  `{ply, move_number, is_white, san, uci, score_cp, loss_cp, quality, best_move,
  fen}` ; le graphe lit `score_cp` (les autres champs servent au marqueur/au
  survol) ;
- GameAnalyzer **écrit déjà** sur chaque objet de `move_history` :
  `move.quality`, `move.centipawn_loss`, `move.eval_before_cp`, `move.eval_after_cp`,
  `move.best_move_uci` (GameAnalyzer.gd:107-112) → MoveList rend les badges dès
  qu'elle est rafraîchie (elle ne l'est **pas** en fin d'analyse : voir M3).

### Taxonomie qualité (ChessMove.Quality, ChessMove.gd:5-16)
`NONE=0, BEST=1, BRILLIANT=2, GREAT=3, EXCELLENT=4, GOOD=5, INACCURACY=6,
MISTAKE=7, BLUNDER=8, MISS=9`.
Symboles (`quality_to_symbol`) : `★` BEST, `!!` BRILLIANT, `!` GREAT, `✓` EXCELLENT,
`(vide)` GOOD, `?!` INACCURACY, `?` MISTAKE, `??` BLUNDER, `X` MISS.
Couleurs (`quality_to_color`) : vert vif / turquoise / bleu / vert clair / gris /
jaune / orange / rouge / rose.
Classification moteur (`GameAnalyzer._classify_move`, ligne ~162) :
- coup == #1 moteur et (pièce non-pion, sans capture) → BRILLIANT ;
- coup == #1 moteur sinon → BEST ;
- sinon perte cp : ≤15 EXCELLENT, ≤40 GOOD, ≤90 INACCURACY, ≤200 MISTAKE,
  >200 BLUNDER.

Conséquence M3 : **ne pas recréer une échelle** — utiliser ces constantes/seuils
(déplacer si besoin `_classify_move` dans le futur `MoveQualityService` pour que le
coach, le graphe et la liste partagent la même logique). `MoveList2D` sait déjà
rendre symboles/couleurs ; il ne rafraîchit que sur `position_changed` /
`move_navigated` : ajouter un rafraîchissement à la fin d'analyse
(`Main._on_analysis_finished` → MoveList) si les qualités sont écrites par
GameAnalyzer.

Conséquence M5 : l'**analyse globale existe déjà côté moteur** (GameAnalyzer produit
un rapport complet par partie) ; il suffit de le **résumer pour le LLM** (stats par
camp + erreurs majeures + acpl/accuracies) au lieu de recalculer.

Conséquence M7 : `white_estimated_elo/black_estimated_elo` du rapport (via
`_estimate_elo`) sont une 2e source pour l'estimation du niveau joueur, à croiser
avec les ratings chess.com importés.

---

## Annexe C — APIs proposées (signatures indicatives, à adapter)

### GDScript
- `MoveQualityService` (class_name, réutilise ChessMove/GameAnalyzer) :
  - `const THRESHOLDS := {excellent=15, good=40, inaccuracy=90, mistake=200}`
  - `static func classify(cp_loss: int, move: ChessMove, best_uci: String) -> ChessMove.Quality`
  - `static func apply_to_moves(moves: Array[ChessMove], evaluations: Array) -> void`
  - `static func group_by_quality(moves: Array[ChessMove]) -> Dictionary`
- `RateLimiter` (autoload `RateLimiter`) :
  - `func is_allowed(provider: String) -> bool`
  - `func register_use(provider: String) -> void`
  - `func wait_estimate(provider: String) -> float`
  - config par provider stockée dans ModelCatalog (`rpm`, `burst`) + défauts en
    constantes.
- `PromptCache` (utilitaire, fichiers JSON dans `user://library/cache/`) :
  - `func get(prompt_hash: String) -> String` / `func store(prompt_hash, text)`
- `TtsSpeaker` (autoload) :
  - signaux `phrase_started(index: int, total: int)`, `speech_finished`,
    `speech_error(msg: String)`
  - `func speak_text(text: String, interrupt: bool = true) -> void`
  - `func stop_all() -> void`
- `ChessComService` (extension) :
  - `signal sync_progress(username: String, month: String, done: int, total: int)`
  - `signal sync_finished(username: String, added: int, months: int)`
  - `func sync_player(username: String, mode: String = "delta") -> void`
- `LogExporter` (utilitaire) : `func export_logs() -> String` (écrit
  `user://logs/rodchess_*.log`, rotation 5, retourne le chemin).

### Java (plugins v2, copier le pattern RodChessUci)
- `RodTts` : `speak(String)`, `stop()`, `setRate(float)`, `setPitch(float)`,
  `setLanguage(String)`, `isAvailable()` ; signaux `tts_started`, `tts_done`,
  `tts_error(String)`.
- `RodShare` (M8) : `shareFile(String path, String mime, String title)` ;
  éventuellement `shareText(String)`.
- Les deux : méthodes annotées `@UsedByGodot`, signaux déclarés via
  `getPluginSignals()` (Set de `SignalInfo`), émission sur `runOnHostThread`.

---

## Décisions v6 — réponses aux questions ouvertes

### D1 — Tailles cibles (ergonomie)
- Référentiel unique : téléphone 360 dp (viewport 450 px ≈ 1,25 px/dp). Toutes les
  tailles UI sont exprimées en **px viewport** via des tokens :
  `touch_min = 60 px` (48 dp), `touch_primary = 70 px` (56 dp) ;
  `font_body = 17 px`, `font_button = 20 px`, `font_caption = 15 px`,
  `font_title = 22 px` ; espacements 8/12/16 dp → 10/15/20 px.
- Validation : appareil de référence = petit écran 360 dp (5") ; grand écran en
  secondaire. Ajustement final ±10 % après test utilisateurs (M1), puis gel des
  tokens.

### D2 — `position_changed` vs animation de navigation (M2)
- **Décision** : conserver l'émission de `position_changed` (Main en dépend pour le
  graphe : `Main._on_game_position_changed`, ligne 122) et le rafraîchissement
  MoveList (inoffensif). Le correctif est le **flag d'animation dans ChessBoard2D**
  (`_on_position_changed` retourne tôt si une animation ±1 est en cours).
- Règle de sécurité : toute action qui change brutalement l'état (reset, chargement
  d'une autre partie, flip) doit **annuler** l'animation en cours (`_clear_active_tweens`
  + reset du flag) avant d'appliquer le nouvel état.
- Test d'abord : cahier de test rapide (10 plis ◀ ▶, drag graphe, flip pendant
  l'animation, chargement d'une autre partie) — voir M2.

### D3 — Qualité des coups & niveaux ELO du moteur
- **Seuils qualité** : conserver ceux de `GameAnalyzer._classify_move`
  (≤15/≤40/≤90/≤200, BEST/BRILLIANT si #1) comme **constantes partagées**
  (`MoveQualityService`, Annexe C) ; validation d'acceptabilité avec un joueur fort
  en beta (collecte), pas de changement de seuils avant retour.
- **ELO moteur** : implémenter d'abord `UCI_LimitStrength` + `UCI_Elo` pour les
  cibles 1320-3190 (support SF 19 confirmé). Pour une cible < 1320 (enfants,
  débutants), utiliser `Skill Level` avec un mapping initial à calibrer :
  `skill = clamp(round((cible_elo - 600) / 120), 0, 20)` (ex. 800 → 2, 1000 → 3,
  1200 → 5) ; l'UI affiche "niveau approximatif" et non un ELO exact ; calibration
  par parties "moteur contre moteur" en mode debug (M7).

### D4 — Politesse réseau & limites (chess.com, Lichess, LLM)
- **chess.com** (API publique sans clé) : 1 requête à la fois, délai ≥ 1,5 s entre
  archives, plafond 12 requêtes/min ; **pas de polling automatique** (synchronisation
  uniquement à la demande via le bouton) ; User-Agent explicite conservé ;
  reprise propre sur 429/5xx.
- **Lichess** (P2) : respecter les en-têtes `X-RateLimit-*` ; rythme prudent
  1 req/s ; token optionnel pour plus de volume.
- **LLM (RateLimiter, M5)** : valeurs par défaut conservatrices, stockées par modèle
  dans ModelCatalog et **modifiables par l'utilisateur** (champ "limites RPM" dans
  les réglages) : Groq 30, OpenAI 60, Anthropic 50, Gemini 15 (gratuit)/60 (payant),
  OpenRouter 20, DeepSeek 60, local = illimité. Retry backoff + jitter sur 429/5xx,
  cache des réponses, SLM local par défaut.

### D5 — Beta : canal & logs
- **Canal unique** : Google Form pour le feedback structuré (champ version, appareil,
  action, attendu/constaté) + groupe de discussion privé (WhatsApp/Telegram) pour les
  échanges rapides ; pas de mélange avec le suivi de bugs du dépôt.
- **Logs** : fichier `user://logs/rodchess_AAAA-MM-JJ_HH-MM-SS.log` (UTF-8, rotation
  5 fichiers de 2 Mo max) ; en-tête : versionName/versionCode, Godot, modèle /
  constructeur, API Android, ABI, résolution, **id de session** (aléatoire par
  lancement) ; contenu : lignes `EngineManager`/godot, SCRIPT ERROR, erreurs réseau
  (statut), début/fin d'analyse, actions TTS/plugin ; **aucune donnée de partie par
  défaut** (option "inclure la partie" jamais active par défaut). Export par partage
  Android (plugin `RodShare`, intent ACTION_SEND) — utilisable sans adb.
- Distribution : Google Play internal testing ou APK signé ; versionCode croissant.

### D6 — `stats_label` & câblage MoveList (M3)
- Contenu actuel confirmé (`Main._on_analysis_finished`, ligne 313) :
  `"⚪ Blancs: %.1f%% (Est. %d ELO)  |  ⚫ Noirs: %.1f%% (Est. %d ELO)…"` +
  mention "[Échantillon court]" si < 12 coups ; mis à jour aussi lors de la
  navigation entre analyses (`AdvantageGraph2D._cycle_analysis`).
- **Décision** : `stats_label` reste la source unique du texte agrégé (aucun bandeau
  de stats dupliqué dans le panneau coups). Pour M3 : ajouter une méthode publique
  `MoveList2D.refresh()` et l'appeler à la fin de `Main._on_analysis_finished`
  (après `update_stored_analyses`, ligne ~335) ; le panneau coups n'ajoute que la
  **perte cp, les mini-barres et les filtres par qualité** (données déjà présentes
  sur `move_history` après analyse, cf. Annexe B).
