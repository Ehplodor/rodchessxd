# Directives et Consignes de Développement - RodChessXD

Ce document rassemble les règles d'or, l'architecture technique, les procédures de mise à jour des versions et les bonnes pratiques à respecter obligatoirement lors de tout développement, refactorisation ou analyse sur le projet **RodChessXD**.

---

## 1. Pastille de Version et Gestion des Versions

### Règle d'or :
Chaque version applicative est pilotée par le paramètre officiel dans `project.godot` :
```ini
[application]
config/version="1.1.0"
```

### Pastille UI (Haut Gauche) :
L'interface de l'application dans [Main.tscn](file:///c:/Dev/RodChessXD/src/ui/Main.tscn) comporte en haut à gauche (TopBar) un conteneur vertical compact (`TitleBox`) :
- Ligne 1 : `AppTitle` (« ♟️ RodChess », police 14 pt, couleur `DesignTokens.TEXT_PRIMARY`)
- Ligne 2 : `VersionLabel` (« v1.1.0 », police 10 pt, couleur `DesignTokens.TEXT_MUTED`)

> [!IMPORTANT]
> - **Encombrement strict** : La pastille ne doit **jamais** occuper plus de place que le libellé initial `RodChess` afin de préserver l'espace mobile horizontal (`TopBar`).
> - **Dynamisme** : `Main.gd` charge la version via `ProjectSettings.get_setting("application/config/version", "1.1.0")`.
> - **Mise à jour systématique** : Lors de toute montée de version (ex. `1.1.0` -> `1.1.1`), incrémenter `config/version` dans `project.godot` et tester son affichage.

---

## 2. Procédure d'Export Web (WASM / HTML5) & Déploiement

### Piège fréquent (Cache & Fichiers périmés) :
Godot n'exporte pas automatiquement le Web lors des modifications en GDScript :
- Les fichiers `RodChessXD2.pck`, `RodChessXD2.wasm`, et `RodChessXD2.html` à la racine sont des artefacts compilés.
- Si le Web présente un comportement différent de la version Desktop (F5), **la première cause est l'exécution d'un export `.pck` non régénéré ou mis en cache par le navigateur**.

### Commande d'exportation Web officielle :
```powershell
& "C:\Dev\tools\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --export-release "Web" "./RodChessXD2.html" --path .
```

### Serveur de test Web local :
Pour tester le Web avec les en-têtes requis pour les SharedArrayBuffer et le multithreading Web :
```powershell
python serve_web.py
```
*(Port `8060` avec `Cross-Origin-Opener-Policy: same-origin` et `Cross-Origin-Embedder-Policy: require-corp`)*.

---

## 3. Boucle d'Analyse du Jeu (KISS & Synchronisation)

Le composant [GameAnalyzer.gd](file:///c:/Dev/RodChessXD/src/engine/GameAnalyzer.gd) gère l'évaluation coup par coup selon le principe KISS, mais doit maintenir la parité fonctionnelle entre les modes Desktop et Web :

1. **Mode Desktop (Thread séparé ou synchrone) :**
   - Utilise `start_game_analysis(moves, fen, ...)` et émet `analysis_position_ready(ply_index, move, fen, score, best_move, ...)`.
   - Si `wait_for_display == true`, le thread de l'analyseur attend la confirmation d'affichage via `confirm_analysis_position_displayed(ply_index)` avant de passer au coup suivant.

2. **Mode Web (Asynchrone dans la boucle principale) :**
   - Utilise `start_game_analysis_async(moves, fen, ...)` avec `await get_tree().process_frame`.
   - Si `wait_for_display == true`, l'analyseur cède la main (`await tree.process_frame`) tant que la position n'a pas été confirmée affichée sur l'échiquier.

3. **Échiquier [ChessBoard2D.gd](file:///c:/Dev/RodChessXD/src/ui/components/ChessBoard2D.gd) :**
   - La navigation séquentielle déclenche un tween de déplacement (`move_anim_duration = 0.18s`).
   - Le signal `navigation_forward_completed` avertit [Main.gd](file:///c:/Dev/RodChessXD/src/ui/Main.gd), qui appelle immédiatement `confirm_analysis_position_displayed(ply_index)` pour débloquer l'analyse du coup suivant.

> [!WARNING]
> Ne jamais supprimer ou découpler `confirm_analysis_position_displayed()` sans vérifier à la fois l'exécution F5 et l'export Web.

---

## 4. Patrons d'Ergonomie et Mobile UI (RodChess Mobile Patterns)

Conformément à `.agents/skills/rodchess-mobile-ui-patterns/SKILL.md` :

1. **Modales (`Window`) :**
   - Toujours appeler `DesignTokens.adapt_modal_size(self, 410, 650)` dans `_ready()`.
   - Ne jamais forcer de largeur supérieure à 410 px en dur (cible mobile 360-420 px).

2. **TopBar & Barres d'outils denses :**
   - Éviter d'entasser trop de contrôles sur un seul `HBoxContainer`.
   - Les `Label` avec texte variable doivent impérativement avoir `text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS`.
   - Les boutons tactiles doivent respecter une hauteur minimale de 40 px (`DesignTokens.TOUCH_DENSE`) à 48 px (`DesignTokens.TOUCH_MIN`).

3. **Scroll tactile :**
   - Tout `ScrollContainer` doit activer `DesignTokens.touch_scroll(self)` et désactiver le défilement horizontal si inutile.

---

## 5. Validation et Tests Automatisés

Avant de valider ou commiter toute modification, exécuter la suite de tests headless :

```powershell
# 1. Vérification de la synchronisation de l'analyse et de l'évolution du plateau (Desktop + Web mock)
& "C:\Dev\tools\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path . -s tests/test_board_evolution_during_analysis.gd

# 2. Vérification des modales et tokens UI mobiles
& "C:\Dev\tools\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path . -s tests/test_ui_modals.gd

# 3. Vérification des statistiques SF19 et live graph
& "C:\Dev\tools\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path . -s tests/test_statistical_analysis.gd

# 4. Vérification de la compilation et absence d'erreurs de syntaxe
& "C:\Dev\tools\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --quit
```
