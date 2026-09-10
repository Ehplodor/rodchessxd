# RodChessXD — Plan d'évolutions : fiabilité d'analyse, outillage moteur, UX

> Plan unique phasé **P0 → P3**, exécutable dans l'ordre par un agent d'implémentation.
> Cible : branche **`main-web`** (source de vérité publiée, cf. skill
> `rodchess-deploiement-git-pwa`). Aucun binaire ni secret ajouté au dépôt.
> Décisions validées le 2026-09-10.

## Objectif

Corriger d'abord la **fiabilité de l'analyse** (classification, mat, faux « brillants »),
puis livrer l'**outillage d'analyse** (multi-PV, ouvertures/théorie, rapport de partie,
motifs), l'**interaction** (annotations, PGN annoté, graphe, horloge, FEN), et enfin le
**coach interactif** (PV cliquable, « et si j'avais joué X ? »).

## Décisions figées

1. **Structure** : un seul plan phasé P0 → P3, tâches ordonnées.
2. **Périmètre v1** : inclut A1–A5, B1, B2, B5, C1–C5, D. **Hors périmètre v1** :
   B3 (Maia « coup humain »), B4 (boîte à erreurs/puzzles), E (hébergement web
   multi-thread / COOP-COEP), i18n EN. Ces points restent « à planifier plus tard ».
3. **Analyses archivées** : ajouter `schema_version` aux nouveaux rapports ; **ne pas**
   recalculer les anciennes ; fournir un bouton **« Ré-analyser »**.
4. **Ouvertures** : table **ECO/ouvertures JSON texte** embarquée (pas de polyglot `.bin`).
5. **Classifieur** : passage à la **perte de probabilité de gain** (win%), seuils
   par défaut type Lichess (inaccuracy ≥ 10 %, mistake ≥ 20 %, blunder ≥ 30 % de
   win% perdu), centralisés/configurables dans `MoveQualityService`.
6. **Multi-PV** : panneau **repliable**, 3 lignes (2 sur mobile), cliquables.
7. **Annotations utilisateur** : persistées dans le JSON de partie (`annotations`).
8. **Motifs tactiques** : détectés localement et fournis comme **faits vérifiés** au coach
   (jamais laissés à l'appréciation du LLM).

## Contraintes transverses (à respecter à chaque tâche)

- Branche `main-web` uniquement ; commit/push selon le skill ; jamais `git add -A`.
- UI : `DesignTokens.adapt_modal_size()`, `DesignTokens.touch_scroll()`, cibles ≥ 40 px,
  `text_overrun_behavior = OVERRUN_TRIM_ELLIPSIS` (cf. skill `rodchess-mobile-ui-patterns`).
- Journaliser les nouveaux flux via `AppLogger` (tags dédiés).
- Aucun nouveau binaire versionné. La table ECO est un `.json` texte.
- Version : `project.godot` `config/version` → `1.2.0` à la livraison de **P0+P1**
  (mettre à jour la pastille, cf. `CONSIGNES-DEV.md` §1).

---

## P0 — Fiabilité de l'analyse (prioritaire)

But : supprimer les affichages faux visibles sur la capture (mat `-100.0`, faux
« brillants ») et rendre la classification cohérente avec l'ACPL/ELO/coach.

### T0.1 — Propagation correcte du mat
- **Constat** : `GameAnalyzer.gd:124-131` force `score_cp = ±10000, mate_in = 0` ; les
  terminaux simulés ne savent pas se dire « mat ». `EvalBar2D.gd:112-119` gère déjà
  `mate_in != 0`.
- **Fichiers** : `src/engine/GameAnalyzer.gd`, `src/engine/EngineManager.gd`,
  `src/ui/Main.gd`, `src/ui/components/AdvantageGraph2D.gd`,
  `src/ui/components/MoveList2D.gd`, `src/core/ChessMove.gd`.
- **Tâches** :
  1. Vérifier/garantir que `evaluate_position_sync()` et `evaluate_position_async()`
     renvoient `mate_in` (sinon l'ajouter au dict de retour).
  2. Dans `GameAnalyzer` (`start_game_analysis` et `_async`), stocker `mate_in` dans
     `move_record` (et sur `ChessMove`) ; pour un mat terminal simulé, `mate_in = ±1`
     (côté maté = négatif) au lieu de 0.
  3. Créer `src/core/EvalFormatter.gd` (`class_name EvalFormatter`) :
     `format_cp_mate(score_cp, mate_in) -> String` (`"M3"`, `"-M2"`, `"+1.4"`, `"−0.6"`).
     Remplacer les 4 formatages dupliqués (`Main.gd:606-610,648-652,666-671`,
     `AdvantageGraph2D.gd:400-417`, `MoveList2D`).
  4. `AdvantageGraph2D` : `eval_to_y` doit mapper un mat sur le haut/bas de l'échelle
     (traiter `mate_in != 0` à part de `score_cp=10000`), et la légende afficher `M`.
- **Acceptation** : une partie terminée par mat affiche `M1/M#` partout (badge, barre,
  graphe, ligne de coup) ; plus aucun `-100.0`/`+100.0`.

### T0.2 — Classification par perte de win%
- **Fichiers** : `src/ui/components/MoveQualityService.gd`, `src/engine/GameAnalyzer.gd`.
- **Tâches** :
  1. Ajouter dans `MoveQualityService` : `const WINPCT_THRESHOLDS := {inaccuracy:10.0,
     mistake:20.0, blunder:30.0}`, et `static func classify(win_before, win_after,
     is_best, move, best_uci, is_sacrifice) -> int`.
  2. Y **déplacer** `_classify_move` (`GameAnalyzer.gd:470-487`) et l'utiliser depuis
     `GameAnalyzer` (source unique de vérité partagée coach/graphe/liste).
  3. Stocker `win_before`/`win_after` (ou perte de win%) dans `move_record` et sur
     `ChessMove` (nouvelles vars `eval_before_cp`, `eval_after_cp` existantes +
     `winpct_loss`). Conserver `loss_cp` pour l'affichage/back-compat.
  4. `_win_percentage` (`GameAnalyzer.gd:501`) reste la référence ; l'exposer via
     `MoveQualityService` pour éviter la duplication.
- **Acceptation** : en position gagnante (+9), un coup perdant 200 cp n'est plus marqué
  « gaffe » ; la classification reflète le basculement réel du résultat.

### T0.3 — Redéfinition de « brillant »
- **Constat** : `GameAnalyzer.gd:470-475` marque `BRILLIANT` dès que le coup est le
  #1 moteur non-pion/non-capture → chapelet de points verts en finale perdue (capture).
- **Fichiers** : `MoveQualityService.gd`, `GameAnalyzer.gd`.
- **Tâches** :
  1. Implémenter `static func is_sacrifice(fen_before, uci, pv) -> bool` : gain matériel
     net sur la PV (≥ pièce mineure) ou offre matérielle non immédiatement regagnée.
  2. `BRILLIANT` **ssi** `played == best` **et** `is_sacrifice` **et** `win_after < 95`.
     Sinon `BEST` (coup #1) / `GREAT` (voir T0.4).
  3. Si aucune PV exploitable, ne jamais produire `BRILLIANT` (repli sur `BEST`).
  4. Limiter la densité visuelle : `AdvantageGraph2D.gd:360-375` n'affiche que les
     `BRILLIANT`/`BLUNDER`/`MISTAKE` — conserver, mais le classifieur corrigé suffit.
- **Acceptation** : sur une finale perdue, plus de série de `BRILLIANT` ; les `!!` sont
  réservés aux sacrifices réels.

### T0.4 — Implémenter `GREAT` et `MISS`
- **Constat** : jamais produits (`GameAnalyzer.gd:31-32,489-497`) alors que l'UI
  (`MoveList2D.gd:19-29`) et le coach (`AICoach.gd:361,373`) les attendent.
- **Fichiers** : `MoveQualityService.gd`, `GameAnalyzer.gd`, `MoveList2D.gd`.
- **Définitions retenues** :
  - `GREAT` : coup = meilleur **et** seul coup préservant le résultat (variante #2,
    si dispo via multi-PV, perd ≥ 15 % de win%) ; sans multi-PV, repli : coup #1 dans
    une position à forte tension (win_before ∈ [30,70] et perte de la meilleure
    alternative estimée ≥ 15 %).
  - `MISS` : chute de win% ≥ seuil blunder **alors que** `win_before ≥ 70`
    (occasion de gain nette gâchée) ; distinct de `BLUNDER` (position non gagnante).
- **Tâches** : ajouter `"miss"` aux dicts `white_stats`/`black_stats` et le brancher
  dans `_increment_quality_stat` ; libellés/symboles déjà présents.
- **Acceptation** : les filtres « ! » et « X » renvoient des coups ; les compteurs ne
  sont plus figés à 0.

### T0.5 — Versionnage des analyses & « Ré-analyser »
- **Fichiers** : `src/engine/GameAnalyzer.gd` (`_build_final_report`),
  `src/ui/components/LibraryModal.gd`, `src/ui/Main.gd`,
  `src/ui/components/MoveList2D.gd` / `AdvantageGraph2D.gd`.
- **Tâches** :
  1. Ajouter `"schema_version": 2` au rapport ; les lecteurs tolèrent l'absence
     (`.get("schema_version", 1)`) et signalent « analyse ancienne » (badge discret).
  2. Bouton **« Ré-analyser »** (Bibliothèque + overlay Analyse) qui recharge la partie
     et relance `_on_btn_analyze_game_pressed` ; l'analyse s'ajoute (`engine_analyses[]`).
  3. Ne rien migrer automatiquement.
- **Acceptation** : ancien rapport s'affiche sans erreur ; « Ré-analyser » produit une
  nouvelle entrée avec `schema_version = 2`.

### T0.6 — Tests P0
- Étendre `tests/test_statistical_analysis.gd` ; créer `tests/test_move_quality.gd`
  (win%, brillant/sacrifice, miss/great, `EvalFormatter`, mat).
- Lancer les commandes headless de `CONSIGNES-DEV.md` §5 (dont `--quit` sans erreur).

---

## P1 — Outillage d'analyse

### T1.1 — Multi-PV réel + panneau des lignes moteur
- **Constat** : `multipv_lines` est déclaré/émis mais **jamais rempli** (`EngineManager.gd:24,1359`).
- **Fichiers** : `src/engine/EngineManager.gd`, nouveau
  `src/ui/components/EngineLinesPanel2D.gd`, `src/ui/Main.tscn`,
  `src/ui/Main.gd`, `src/core/SettingsManager.gd`.
- **Tâches** :
  1. `EngineManager` : à `start_engine`/`set options`, envoyer
     `setoption name MultiPV value N` (réglage `engine_multipv`, défaut 3, clamp 1-5,
     2 sur mobile). Parser le token `multipv` dans `_parse_engine_line` et **accumuler**
     `multipv_lines[rank] = {depth, score_cp, mate_in, pv}` par génération (vider à
     chaque nouvelle `_evaluation_generation`).
  2. Nouveau `EngineLinesPanel2D` : 1 ligne par PV (rang, SAN/PV décodée via
     `ChessGame.format_pv_natural_text`, éval `EvalFormatter`) ; clic → prévisualisation
     (flèche plateau + position de la PV sans modifier la partie) ; repliable.
  3. Insertion : sous `GraphPanel` dans `Dashboard` (portrait) ; s'adapte en paysage
     via `Main._dock_overlay`/`_apply_adaptive_layout`.
  4. Réglage MultiPV dans `SettingsModal`.
- **Acceptation** : 3 lignes affichées et cohérentes avec le score ; clic → aperçu ;
  coût CPU maîtrisé (N=2 sur mobile).

### T1.2 — Ouvertures & détection de théorie (A5)
- **Fichiers** : nouveau `assets/openings/eco_openings.json` (texte, sous-ensemble
  curaté : séquence UCI → `{eco, name}`), nouveau `src/core/OpeningBook.gd`
  (`class_name OpeningBook`, `RefCounted`), `src/engine/GameAnalyzer.gd`,
  `src/ui/components/MoveList2D.gd`, `src/ai/AICoach.gd`.
- **Tâches** :
  1. `OpeningBook.identify(moves_uci) -> {eco, name, out_of_book_ply}` (plus longue
     correspondance).
  2. `GameAnalyzer` marque `is_theory` sur les plies dans la séquence connue ;
     **exclure** ces plies de l'ACPL/précision/ELO (compteurs séparés) et arrêter le
     marquage au premier coup hors livre.
  3. `MoveList2D` : nom d'ouverture en en-tête + badge « théorie » (sans symbole de
     qualité).
  4. `_detect_game_phase` du coach (`AICoach.gd`) peut s'appuyer sur la sortie de livre.
- **Acceptation** : une partie italienne/espagnole affiche nom + ECO ; les coups de
  théorie ne faussent plus ACPL/ELO ; hors-livre = analyse normale.

### T1.3 — Rapport de partie « Game Review » (B2)
- **Fichiers** : nouveau `src/core/GamePhaseService.gd`, nouveau
  `src/ui/components/GameReviewPanel2D.gd` (ou section dans l'overlay Analyse),
  `src/ui/Main.gd`, `src/engine/GameAnalyzer.gd`.
- **Tâches** :
  1. `GamePhaseService.classify(fen, ply, out_of_book_ply) -> phase`
     (ouverture → sortie de livre/max ~ply 20 ; milieu ; finale via matériel/absence
     de dames) ; factoriser la logique de `AICoach._detect_game_phase`.
  2. Ajouter au rapport : précision par phase et par camp, distribution des qualités,
     top 3 « plus gros basculements de win% » (`{ply, san, winpct_loss}`).
  3. UI : barres de distribution, précision par phase, moments clés cliquables
     (→ `navigate_to_ply`). Réutiliser `MoveQualityService`.
- **Acceptation** : le rapport s'affiche, les moments clés naviguent, tout est dérivé du
  rapport existant (aucune persistance nouvelle).

### T1.4 — Détection de motifs tactiques (B5)
- **Fichiers** : nouveau `src/core/TacticalMotifDetector.gd`, `src/engine/GameAnalyzer.gd`,
  `src/ui/components/MoveList2D.gd`, `src/ai/AICoach.gd`.
- **Tâches** :
  1. `TacticalMotifDetector.detect(fen_before, uci, pv) -> Array[String]` : fourchette,
     enfilade/clouage (rayons), attaque à la découverte, mat du couloir, pièce non
     défendue/en prise, attaque double, déviation. Approches heuristiques via
     `ChessGame` (cartes d'attaques), pas de calcul lourd.
  2. Stocker `motifs` dans `move_record` ; afficher en puces dans la liste des coups.
  3. `AICoach.build_prompt_data` : ajouter une ligne « Motifs détectés (vérifiés) » dans
     la fiche technique et adapter la règle anti-hallucination (le LLM **ne détecte plus**,
     il explique).
- **Acceptation** : les motifs listés sont exacts sur un jeu de positions tests ; le
  prompt contient les motifs vérifiés.

### T1.5 — Tests P1
- `tests/test_multipv_parsing.gd`, `tests/test_opening_book.gd`,
  `tests/test_game_review.gd`, `tests/test_tactical_motifs.gd` (fixtures locales).

---

## P2 — Interaction & exports

### T2.1 — Annotations utilisateur (C1)
- **Fichiers** : `src/ui/components/ChessBoard2D.gd`, `src/core/GameController.gd`,
  `src/core/DatabaseManager.gd`.
- **Tâches** : flèches (clic droit / glisser secondaire) et cercles de case ; stockage
  par `ply` dans le JSON de partie (`annotations`), rechargé au chargement ; bouton
  effacer ; respect du thème. Conserver les flèches moteur distinctes.
- **Acceptation** : annotations visibles, persistées après rechargement, effaçables.

### T2.2 — Export PGN annoté (C2)
- **Fichiers** : `src/core/ChessGame.gd` (`export_pgn`), `src/ui/Main.gd`,
  `src/ui/components/PGNModal.gd`.
- **Tâches** : `export_pgn(include_annotations := false)` ; mapper les qualités en NAG
  (`$1` bon, `$2` erreur, `$3` brillant, `$4` gaffe, `$5` intéressant, `$6` douteux) et
  insérer `{commentaire}` (coach/user). Entrée de menu « Copier le PGN annoté ».
- **Acceptation** : le PGN rechargé dans Lichess/Chess.com conserve annotations/NAG.

### T2.3 — Améliorations du graphe (C3)
- **Fichiers** : `src/ui/components/AdvantageGraph2D.gd`.
- **Tâches** : infobulle survol/tap (coup + éval) ; zones « décidées »/mat ; repères de
  phase ; superposition optionnelle de plusieurs analyses archivées (au lieu du seul
  cyclage `_cycle_analysis`) ; zoom/pan **optionnel** (à marquer nice-to-have).
- **Acceptation** : infobulle fiable, phases lisibles, superposition désactivable.

### T2.4 — Horloge & pression temporelle (C4)
- **Fichiers** : `src/core/ChessGame.gd` (parseur PGN), `src/core/DatabaseManager.gd`
  (`moves_arr`), `src/ui/components/MoveList2D.gd`, rapport P1.
- **Tâches** : capturer les commentaires `{[%clk H:MM:SS]}` → `clock_sec` par coup ;
  afficher l'horloge dans la liste ; ajouter au rapport « temps moyen/coup » et
  « précision sous faible temps restant » **quand la donnée existe** ; sinon masquer.
- **Acceptation** : aucune régression sur les PGN sans horloge ; stats affichées quand
  présentes.

### T2.5 — Import FEN rapide (C5)
- **Fichiers** : `src/ui/Main.gd` (menu Importer), `src/ui/components/OCREditorModal.gd`.
- **Tâches** : entrée « Coller une FEN » réutilisant le champ FEN + palette existants de
  `OCREditorModal` (source `fen_import`) ; éventuellement éditeur de position minimal.
- **Acceptation** : coller une FEN charge la position et l'analyse Live.

### T2.6 — Tests P2
- `tests/test_pgn_annotations.gd`, `tests/test_clock_parsing.gd`,
  `tests/test_annotations_persistence.gd`.

---

## P3 — Coach interactif

### T3.1 — PV cliquable
- **Fichiers** : `src/ui/components/CoachPanel2D.gd`, `src/ui/components/ChessBoard2D.gd`.
- **Tâches** : rendre les coups SAN des réponses/PV cliquables → prévisualisation de la
  position correspondante (flèche + plateau, sans altérer l'état de la partie).
- **Acceptation** : cliquer un coup de la ligne affiche la position, retour possible.

### T3.2 — « Et si j'avais joué X ? » (what-if)
- **Fichiers** : `src/core/GameController.gd`, `src/engine/EngineManager.gd`,
  `src/ui/components/CoachPanel2D.gd`, `src/ai/AICoach.gd`.
- **Tâches** : mode bac à sable (jouer un coup alternatif sans modifier la partie) ;
  évaluation moteur de la position obtenue ; comparaison win% (`MoveQualityService`)
  vs coup joué ; le coach commente le delta. Réutiliser T1.4 (motifs) et T0.2.
- **Acceptation** : le what-if ne corrompt pas l'historique ; delta de win% affiché.

### T3.3 — Tests P3
- `tests/test_whatif_sandbox.gd` (non destructif), vérif prompt enrichi.

---

## Validation globale

1. Commandes headless (cf. `CONSIGNES-DEV.md` §5) : `test_board_evolution_during_analysis`,
   `test_ui_modals`, `test_statistical_analysis`, puis `--quit` sans `SCRIPT ERROR`.
2. Nouveaux tests P0→P3 ci-dessus.
3. Test manuel Desktop (F5) **et** export Web/PWA (régénérer l'export, cf. skill) :
   analyser une partie réelle, vérifier mat, brillants, multi-PV, rapport, motifs,
   annotations, export PGN annoté, what-if.
4. Mobile : `adapt_modal_size`, zones sûres, scroll tactile, multi-PV limité à 2.
5. Mettre à jour `docs/FICHE_ETAT_RodChessXD.md` et la roadmap M3–M7 (marquer les
   jalons couverts) ; bump `config/version` → `1.2.0` après P0+P1.

## Risques & mitigations

- **Calibration des seuils win%** : à valider avec un joueur fort (beta) ; seuils
  centralisés donc ajustables sans refonte.
- **Coût multi-PV sur mobile** : N=2 mobile, repliable, mesurer batterie.
- **Table ECO** : couverture limitée ; ne jamais bloquer l'analyse ; `out_of_book_ply`
  prudent (ne pas sur-exclure de la théorie).
- **Motifs heuristiques** : faux négatifs possibles → présenter comme « indices
  vérifiés » ; réserver les affirmations fortes au moteur.
- **Persistance annotations/horloge** : champs additifs, lecteurs tolérants ;
  compatibilité anciennes parties garantie.
- **Web** : vérifier que multi-PV et motifs ne dégradent pas le mono-thread WASM
  (limiter la profondeur côté web si besoin).

## Questions résiduelles (non bloquantes, ajustables à l'implémentation)

1. Seuils exacts win% (10/20/30 par défaut) — à confirmer en beta.
2. Zoom/pan du graphe (T2.3) : nice-to-have, inclure seulement si le budget UI le permet.
3. Éditeur de position complet (au-delà du collage FEN) : hors périmètre v1.

## Hors périmètre v1 (à planifier ultérieurement)

B3 Maia « coup humain » (desktop/lc0), B4 boîte à erreurs & puzzles avec répétition
espacée, E hébergement web multi-thread (COOP/COEP), i18n EN.
