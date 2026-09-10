# Fiche d'état — RodChessXD

> Application d'échecs mobile **Godot 4.7.1** (GDScript), avec analyse par **Stockfish** et **Coach IA** (LLM multi-fournisseurs).
> Base documentaire : `.kilo/plans/ROADMAP_PROCHAINES_ETAPES.md` (feuille de route).

---

## 1. Architecture

- **Moteur / langage** : Godot 4.7.1 (stable), GDScript, rendu mobile ; projet portrait, viewport de base 450×800 px (~1,25 px/dp).
- **Organisation du code**
  - `src/core` : logique de jeu (`ChessGame`, `ChessMove`, `ChessPiece`, `GameController`) et analyse (`GameAnalyzer`).
  - `src/engine` : interface moteur d'échecs (`EngineManager`) + adapter Android.
  - `src/ui` : écran principal (`Main`) + composants 2D ; `src/ui/theme/DesignTokens.gd` = tokens UI (jalon M1).
  - `src/coach` : `AICoach` (appels LLM), `ModelCatalog`, `LocalSLMManager`, téléchargements.
  - `addons` / `android` / `tools` : plugin natif Android et outillage de validation.
  - `tests` : scénarios de test Godot (`SceneTree`) ; validation d'exécution via scènes temporaires headless.
- **Singletons (autoloads)** : `SettingsManager`, `DatabaseManager`, `ModelCatalog`, `ModelDownloader`, `LocalSLMManager`, `GameController`, `EngineManager`, `AICoach`.
- **Persistance** : fichiers JSON indexés (`user://library/games_index.json` + un fichier par partie), pas de SQLite.

---

## 2. Fonctionnalités principales

### Jeu & plateau
- Échiquier 2D avec pièces, coups légaux, roque, prise en passant, échec/échec et mat.
- **Retournement du plateau** (persisté), navigation temporelle par coups (début / précédent / suivant / fin), animations de déplacement et FX de capture.
- **Sons** (déplacement, capture, échec), activation/désactivation.

### Moteur d'échecs & analyse
- **Stockfish** intégré : local (bureau) et **Android via plugin natif** (`RodChessUci`, AAR Gradle, exécuté depuis `nativeLibraryDir`).
- Évaluation en continu (score cp / mat), meilleur coup + ligne principale (PV).
- **Analyse globale d'une partie** (`GameAnalyzer`) : évaluation coup par coup, **qualité des coups** (bon / imprécision / erreur / gaffe…), perte en centipawns, **précisions %** et **ELO estimé** par camp, statistiques (Blancs/Noirs).
- **Graphique d'avantage** (courbe d'évaluation, multi-analyses archivées, scrubbing vers le coup), **barre d'évaluation**, **liste des coups** avec badges de qualité, flèche du coup joué.

### Coach IA
- Conseils en langage naturel sur la position, dans une **perspective** choisie (Blancs / Noirs / Neutre).
- Contexte automatique envoyé : FEN, évaluation, ligne principale, dernier coup (SAN/UCI), qualité/perte cp.
- **Multi-fournisseurs** : modèles gratuits/API clés/SLM local, gestion des clés, estimation des coûts.
- **Conversation en chat** (transcription accumulée), **prompts prédéfinis par tuiles**, question libre, **historique archivé** par partie.

### Import / bibliothèque
- **PGN** (coller/ouvrir), **photo d'un échiquier → OCR** (édition puis validation), **synchronisation Chess.com** (jeux publics d'un pseudo).
- **Bibliothèque** : parties & analyses archivées (chargement, suppression, historique Coach, analyses moteur enregistrées).
- **Hub moteur** (install/gestion des moteurs), **Hub modèles IA**.

### Ergonomie mobile
- Tokens UI centralisés, cibles tactiles ≥ 60 px, polices AA (15–22 px), **zones sûres** (encoche, barre de gestes).
- **Défilement tactile** (drag direct + ascenseurs larges), thème sombre cohérent.

---

## 3. Évolutions déjà réalisées

1. **Stockfish fonctionnel sur Android** — découverte et exécution du binaire natif via un plugin Android (`ProcessBuilder` depuis `nativeLibraryDir`), contournement des limites SELinux (`user://` → dossier natif), correctif de routage des chemins (`/data/...` vs `user://`).
2. **Durcissement `EngineManager`** — découverte tolérante du dossier natif, contrôle de validité ELF, **auto-réparation** (copie du moteur vers `user://`, chmod, relance, persistance du chemin), **diagnostics runtime** Android (stades « introuvable / échec de démarrage »), tests de régression purs (parsing du répertoire natif).
3. **Jalon M1 — Ergonomie & accessibilité** *(terminé et validé, sept. 2026 — cf. feuille de route, section M1)* — création de `DesignTokens` (tailles, cibles tactiles, palette AA), barre haute refaite (boutons 46×60, menu **Importer**), onglets bas restylés, audit complet des tailles en dur, contrastes corrigés (WCAG AA), retour à la ligne intelligent, **zones sûres** dynamiques.
4. **Défilement tactile** — ascenseurs élargis et **glissé direct** sur les listes/ScrollContainer (dont les listes remplies de boutons).
5. **Coach : vraie zone de conversation** — transcript chat enrichi et **prompts par tuiles** (fenêtre dédiée non scrollable, perspective intégrée).
6. **Libellés des joueurs** en haut/bas du plateau (pastille de couleur + nom), masqués quand inconnus, suivant l'orientation du plateau.
7. **Jalon M2 — Navigation temporelle fluide** *(livré sept. 2026 — cf. feuille de route, section M2)* — garde d'animation plateau (`is_animating_move`), **annulation propre au retournement**, **scrub du graphe throttlé (~90 ms)** (marqueur instantané + navigation unique au relâchement) ; transitions journalisées via `AppLogger` (tag `NAV`). Le libellé ply permanent est couvert par le HUD du graphe.
8. **Jalon M8 — Observabilité (beta)** *(noyau livré sept. 2026)* — autoload `AppLogger` (`user://logs/rodchess_*.log`, rotation 5, id de session, en-tête version/appareil) + section **« À propos & Logs »** dans les Réglages avec **Exporter les logs**. Hors code : partage Android par intent (plugin `RodShare`), distribution Google Play, feedback/matrice testeurs.
9. **Correctif plateau disparu** — erreur de parse `ChessBoard2D` (`var flipped := gc.board_flipped …` : Variant non inférable) corrigée par `bool(...)`, **validée en headless** (aucune SCRIPT ERROR) puis APK ré-exporté et réinstallé sur téléphone.
10. **Fiabilité de l'analyse (P0, v1.2.0)** — classe `EvalFormatter` (mat « M3/-M2 » au lieu de « ±100.0 ») propagée partout ; classification des coups par **perte de probabilité de gain** (`MoveQualityService`, seuils 10/20/30) ; `BRILLIANT` désormais réservé à un **sacrifice réel** (`is_sacrifice` sur la PV) ; `GREAT` (seul coup préservant le résultat, via MultiPV) et `MISS` (gain gâché) réellement produits ; `schema_version` du rapport + bouton **Ré-analyser** (les analyses archivées restent inchangées).
11. **Lignes moteur MultiPV (P1)** — `EngineManager` envoie `MultiPV N`, accumule les lignes par rang (`multipv_lines`) et les expose ; nouveau panneau repliable `EngineLinesPanel2D` (SAN + éval, clic → aperçu sur l'échiquier) ; réglage MultiPV dans les Réglages ; MultiPV réduit (2 bureau / 1 mobile) pendant l'analyse de masse.
12. **Ouvertures & théorie (P1)** — `OpeningBook` + table `assets/openings/eco_openings.json` (texte, sans binaire) : nom/ECO affiché en tête de liste, et **exclusion des coups de théorie** de l'ACPL, de la précision et de l'ELO.
13. **Rapport de partie & motifs (P1)** — `GamePhaseService` (ouverture/milieu/finale, `GameReviewPanel2D` : précision, distribution, moments clés cliquables) et `TacticalMotifDetector` (fourchette, enfilade, découverte, mat du couloir, pièce en prise) fournis comme **faits vérifiés** au coach (plus d'invention LLM).
14. **Interaction & exports (P2)** — annotations utilisateur (flèches/cercles clic droit ou Maj+glisser) **persistées par position** ; **export PGN annoté** (NAG + commentaire + `%clk`, compatible Lichess/Chess.com) ; lecture des horloges `[%clk]` des PGN ; repères de phase sur le graphe ; **import FEN** depuis le presse-papiers.
15. **Version `1.2.0`** — `project.godot` mis à jour (pastille affichée automatiquement).

> Restent au programme (hors périmètre v1) : B3 Maia « coup humain », B4 boîte à erreurs/puzzles, hébergement web multi-thread (COOP/COEP), i18n EN, ainsi que le PV cliquable / « et si j'avais joué X ? » du coach (P3).

---

## 4. Prochaines évolutions en vue (roadmap)

Ordre recommandé dans la feuille de route (M1, M2 et M8 livrés) : **M3+M4** ensuite, **M5+M6** en parallèle, **M7** exploratoire.

| Jalon | Contenu visé | Effort |
|---|---|---|
| **M3** | Coups groupés par qualité (service partagé, mini-barres, filtres, perte cp) — base M2 livrée | M |
| **M4** | Synthèse vocale (TTS) des commentaires du coach — selon le pattern plugin Android validé | M |
| **M5** | Coach IA : cache + fallback + rate-limiter (anti-bannissement), architecture autour des `_request_*` de `AICoach` | L |
| **M5+** | **Marqueurs d'annotations Coach sur le graphe & joueurs** — afficher un icône visuel interactif (pastille de point de vue `⚪/⚫/⚖️`) sur le graphe d'avantage au niveau de chaque coup ayant bénéficié d'une explication du coach, et au niveau du joueur concerné, permettant de se positionner instantanément sur le coup et d'accéder aux conseils | M |
| **M6** | Synchronisation / sauvegarde (repose sur l'index JSON `user://`) | M |
| **M7** | Estimation ELO plus poussée (dépend de M3 et M6) | L |

Notes transverses :
- La validation de confiance des scripts est le **chargement headless Godot** (le parseur `gdtoolkit` ne suffit pas) ; tests via petites scènes temporaires (les `tests/test_*.gd` ne voient pas les autoloads).
- L'émulateur x86_64 ne peut pas exécuter le binaire Stockfish arm64 : validation moteur sur téléphone réel, validation UI possible sur émulateur.
