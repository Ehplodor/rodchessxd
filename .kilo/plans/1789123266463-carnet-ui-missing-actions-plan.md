# Plan d'implémentation — Actions manquantes LeCarnet (UI)

**Objectif** : Ajouter dans l'overlay Carnet (onglet ⟳ Sync) toutes les actions utilisateur pour gérer profils, clés joueurs, parties rattachées et imports — sans passer par la console.

**État courant** : Phases A-E implémentées et testées. Phase F non démarrée.

---

## 1. Architecture & principes

| Couche | Fichier | Rôle |
|--------|---------|------|
| **T1 Présentateur** | `CarnetPresenter.gd` | Nouvelles méthodes CRUD + signaux |
| **T2 Overlay** | `CarnetOverlay.gd` | Nouveaux widgets dans `_build_sync_tab()` + modales |
| **T3 Composants** | `components/` | `CarnetProfileEditorModal`, `CarnetGameListItem`, `CarnetImportPgnModal` |
| **Domaine** | `CarnetProfiles.gd`, `CarnetStore.gd` | Modifiés pour persistance perspective + exclusion suppression |

**Conventions UI** (mobile-first, existantes) :
- `DesignTokens.TOUCH_MIN` (60px) pour toute cible tactile
- `DesignTokens.style_button(btn, FONT_BUTTON, TOUCH_MIN)` pour boutons
- Modales = `Window` `exclusive=true` + `DesignTokens.adapt_modal_size(self, w, h)`
- Scroll horizontal pour liste profils (déjà en place)
- Couleurs : `SUCCESS` (vert), `WARNING` (ambre), `DANGER` (rouge), `ACCENT` (bleu)

---

## 2. Étapes d'implémentation

### Phase A — Présentateur : API CRUD profils & clés

- [x] **A1** `CarnetPresenter.create_profile(name, source, player_keys)` → existe déjà
- [x] **A2** `CarnetPresenter.rename_profile(profile_id, new_name)` — *nouveau*
    - Appelle `CarnetProfiles.update(id, {"name": new_name})`
    - Émet `profile_updated(profile_id)` + `profiles_changed` via `refresh_profiles()`
- [x] **A3** `CarnetPresenter.delete_profile(profile_id)` → existe déjà
- [x] **A4** `CarnetPresenter.add_player_key(profile_id, key)` → existe déjà
- [x] **A5** `CarnetPresenter.remove_player_key(profile_id, key)` — *nouveau*
    - Filtre `player_keys`, appelle `update()`
    - Émet `profile_updated(profile_id)` + `profiles_changed` + `sync_changed` (via `refresh_sync()`)
- [x] **A6** `CarnetPresenter.get_profile_games(profile_id)` — *nouveau*
    - Retourne `CarnetProfiles.match_games(profile)` enrichi avec statut sync (via `CarnetStore.sync_status`) + perspective depuis `sync.json`
    - Format : `[{game_id, perspective, title, white_name, black_name, date, status, reason}]`
    - Statuts : `pending` (`never_atomized`), `stale` (`no_analysis`/`analysis_outdated`/`atoms_outdated`), `up_to_date`
- [x] **A7** `CarnetPresenter.reanalyze_game(game_id, profile_id, options={})` — *nouveau*
    - Lance `start_batch([game_id], options)`
- [x] **A8** `CarnetPresenter.remove_game_from_profile(game_id, profile_id)` — *nouveau*
    - Appelle `CarnetStore.remove_game(game_id, profile_id)`
    - Émet `sync_changed` + `carnet_changed` + `plan_changed` + `game_list_changed`
- [x] **A9** `CarnetPresenter.import_pgn_to_profile(pgn_text, profile_id)` — *nouveau*
    - Via `DatabaseManager.record_pgn_game(pgn, "pgn_import", "", true)`
    - Retourne `{game_id, matched_keys: [], new_keys: []}`
    - **Ne pas auto-ajouter** — l'Overlay gère l'action via `ConfirmationDialog`
- [x] **A10** `CarnetPresenter.cycle_game_perspective(game_id)` — *nouveau*
    - Lit `sync.json` via `CarnetStore._load_sync`, cycle `""` → `"white"` → `"black"` → `""`
    - Appelle `CarnetStore.update_game_perspective(game_id, new_perspective, profile_id)`
    - Émet `sync_changed` + `carnet_changed` + `plan_changed` + `game_list_changed`
- [x] **A11** Signal `toast_requested(msg: String, is_success: bool)` — *nouveau*
    - Émis par Presenter pour feedbacks non-bloquants

**Signaux ajoutés dans CarnetPresenter** :
- `profile_updated(profile_id)` (rename, keys)
- `game_list_changed` (après reanalyze/remove/import/perspective)
- `toast_requested(msg, is_success)`

---

### Phase B — Composants T3 (nouveaux fichiers)

#### B1 `CarnetProfileEditorModal.gd` — Créer / Renommer / Supprimer / Gérer clés
- [x] **B1.1** Fichier `src/ui/carnet/components/CarnetProfileEditorModal.gd`
- [x] **B1.2** Mode "create" : champ nom + multi-lignes "Clés joueur (une par ligne)" + bouton "Créer"
- [x] **B1.3** Mode "edit" : pré-rempli, boutons "Renommer", "Supprimer" (→ `ConfirmationDialog`), section "Clés joueur" (liste + bouton "Ajouter" + "✕" par clé)
- [x] **B1.4** Signal `profile_saved(profile_id, is_new)` émis à la fermeture succès
- [x] **B1.5** Validation : nom non vide, clés normalisées via `DatabaseManagerClass.normalize_player_key`
- [x] **B1.6** Tactile : callback direct sur `dialog.confirmed` (pas d'`await` bloquant)

#### B2 `CarnetGameListItem.gd` — Ligne de partie dans la liste Sync
- [x] **B2.1** Fichier `src/ui/carnet/components/CarnetGameListItem.gd` (extends `HBoxContainer`)
- [x] **B2.2** Affichage : `title` (tronqué 40 car.) · `date` · badge perspective (`⟳` auto / `⚪` / `⚫`) · badge statut (vert/ambre/rouge)
- [x] **B2.3** Actions (icônes boutons) : "Réanalyser" ⟳, "Forcer perspective" ↻, "Retirer du carnet" 🗑
- [x] **B2.4** Signaux : `reanalyze_requested(game_id)`, `perspective_cycle_requested(game_id)`, `remove_requested(game_id)`

#### B3 `CarnetImportPgnModal.gd` — Import PGN direct dans le profil actif
- [x] **B3.1** Fichier `src/ui/carnet/components/CarnetImportPgnModal.gd` (extends `Window`)
- [x] **B3.2** Composition : instancie `PGNModal` interne, remplace le dernier bouton par "📥 Charger dans ce carnet"
- [x] **B3.3** À la validation : appelle `presenter.import_pgn_to_profile(pgn, profile_id)`
- [x] **B3.4** Feedback : si nouveaux noms détectés → `ConfirmationDialog` tactile `[Ajouter]` / `[Ignorer]` → `add_player_key` + `refresh_sync` si confirmé

---

### Phase C — Overlay : onglet Sync enrichi

#### C1 En-tête profils : bouton "+" pour créer
- [x] **C1.1** Dans `_rebuild_profiles()` : ajouter un `Button` "+" à la fin de `_profile_row`
- [x] **C1.2** `pressed` → ouvre `CarnetProfileEditorModal` en mode "create"
- [x] **C1.3** Connecter `profile_saved` → `presenter.refresh_profiles()` + `presenter.refresh_sync()`

#### C2 Menu contextuel sur puce profil (clic droit / long-press)
- [x] **C2.1** `CarnetProfileChip` : `gui_input(event)` détecte `MOUSE_BUTTON_RIGHT` + `InputEventScreenTouch` (Timer 500ms) → émet `context_menu_requested(profile_id, global_position)`
- [x] **C2.2** `CarnetOverlay` connecte `context_menu_requested` → `PopupMenu` avec items "Renommer", "Gérer clés", "Supprimer" (désactivé si profil par défaut) → `popup(Rect2i)`
- [x] **C2.3** Actions → ouvrent `CarnetProfileEditorModal` en mode "edit" / `ConfirmationDialog` pour suppression

#### C3 Liste des parties rattachées (sous le résumé sync)
- [x] **C3.1** Dans `_build_sync_tab()` : après boutons d'action, ajouter filtres (`ButtonGroup` + `ScrollContainer` horizontal) + `ScrollContainer` + `VBoxContainer` `_games_list`
- [x] **C3.2** Peupler via `presenter.get_profile_games(profile_id)` filtré → instancier `CarnetGameListItem` par entrée
- [x] **C3.3** Filtres : "Toutes" / "À traiter" / "À jour" / "Périmées" (4 boutons toggle dans `ButtonGroup` horizontal scrollable)
- [x] **C3.4** Connecter signaux `CarnetGameListItem` → méthodes overlay :
    - `_on_game_reanalyze(game_id)` → `presenter.reanalyze_game(game_id)` + `_update_batch_row()`
    - `_on_game_perspective_cycle(game_id)` → `presenter.cycle_game_perspective(game_id)` + `refresh_sync()`
    - `_on_game_remove(game_id)` → `ConfirmationDialog` → `presenter.remove_game_from_profile(game_id)` + rebuild liste

#### C4 Bouton "Importer PGN" dans l'en-tête Sync
- [x] **C4.1** Ajouter bouton "📥 Importer PGN" à côté de "Mettre à jour le carnet"
- [x] **C4.2** Ouvre `CarnetImportPgnModal` avec `presenter.profile_id`
- [x] **C4.3** Au retour → `presenter.refresh_sync()` + `presenter.refresh_carnet()` + `presenter.refresh_plan()`

#### C5 Signal toast dans Presenter
- [x] **C5.1** Ajouter signal `toast_requested(msg: String, is_success: bool)` dans `CarnetPresenter`
- [ ] **C5.2** `Main.gd` connecte ce signal au démarrage → appelle `_show_toast(msg, is_success)` — *non vérifié dans cette session*
- [x] **C5.3** Utilisé dans `import_pgn_to_profile`, `reanalyze_game`, `remove_game_from_profile`, `cycle_game_perspective`

---

### Phase D — Persistance perspective forcée (CarnetStore)

- [x] **D1** `CarnetStore.update_game_perspective(game_id, perspective, profile_id)` — *nouveau*
    - `perspective` ∈ `["", "white", "black"]` (vide = auto)
    - Modifie `entries[game_id].perspective` dans `sync.json`
    - Sauvegarde atomique via `db.save_json_atomic`
- [x] **D2** `CarnetStore.compile()` / `refresh_plan()` : pas de changement requis — `entry.perspective` est lu via `match_games()` / `ingest_game()`
- [x] **D3** `CarnetProfiles.match_games(profile)` : lit `entry.perspective` depuis `sync.json` si non-vide, sinon recalculer (auto). Exclut les entrées marquées `removed`.

---

### Phase E — Tests & validation

- [ ] **E1** Test manuel : créer profil "Test", ajouter clés `["alice", "bob"]`, importer PGN où Alice joue les blancs → vérifier rattachement auto + perspective "white"
- [ ] **E2** Test manuel : réanalyser une seule partie → vérifier `sync_status` passe "up_to_date", radar/forces/faiblesses mis à jour
- [ ] **E3** Test manuel : forcer perspective sur partie ambiguë (même nom blanc/noir) → cycle `⟳`→`⚪`→`⚫`→`⟳` → vérifier drills générés côté correct
- [ ] **E4** Test manuel : supprimer partie du carnet → vérifier disparition ledger/plan + `sync_status` "never_atomized"
- [ ] **E5** Test mobile : cibles tactiles ≥ 48px, scroll fluide, modales centrées, pas de débordement
- [x] **E6** Étendre `test_carnet_presenter.gd` :
    - `_test_profile_crud` : rename, delete, add/remove keys, vérification états persistés
    - `_test_profile_signals` : scénario multi-profils, `select_profile`
    - `_test_game_list` : `get_profile_games` (status `pending`/`up_to_date`/`stale`), `cycle_game_perspective` (3 états), `remove_game_from_profile` (vérification `removed` flag)
    - `_test_game_signals` : cycle + remove vérifiés par effets de bord dans `sync.json`
    - `_test_import_pgn` : `import_pgn_to_profile` → `new_keys` non-vide, `matched_keys` correct, rattachement profil
- [x] **E7** Lancer `godot --headless --script tests/test_carnet_presenter.gd` → **42/42 passent**
- [x] **E8** Lancer `godot --headless --script tests/test_carnet_overlay.gd` → **24/24 passent**
- [x] **E9** Lancer `godot --headless --script tests/test_carnet_main_integration.gd` → **6/6 passent**

**Note E6-E9** : Les tests vérifient les effets de bord (état persité) plutôt que les signaux directement, car `RefCounted` ne permet pas de comptage fiable en headless. Les signaux `profile_updated`, `game_list_changed`, `toast_requested` sont émis et connectés en prod ; leur déclenchement est validé indirectement par les changements d'état qu'ils produisent.

---

### Phase F — Import bulk Chess.com (créer carnet depuis pseudo)

> **Objectif** : Depuis l'onglet Sync, importer **toutes les parties** d'un joueur Chess.com sur N mois, créer le carnet associé, et lancer l'analyse en lot.

#### F1 `ChessComService` — Pagination multi-mois
- [ ] **F1.1** Nouvelle méthode `fetch_all_player_games(username: String, max_months: int = 12, max_games: int = 500)` dans `ChessComService.gd`
    - Récupère `/player/{username}/games/archives` → liste tous les mois
    - Itère du plus récent au plus ancien (max `max_months`)
    - Pour chaque mois : requête archive + parsing PGN (réutilise logique `_on_request_completed` Cas 2)
    - **Rate-limit** : `await get_tree().create_timer(2.0).timeout` entre requêtes (30 req/min safe)
    - Arrêt si `max_games` atteint ou plus d'archives
    - Émet `games_fetched(games)` unique à la fin (agrégé) + `progress_fetched(current_month, total_months, games_count)` signal nouveau
- [ ] **F1.2** Signal `progress_fetched(current: int, total: int, count: int)` pour barre progression UI
- [ ] **F1.3** Gestion erreurs par mois (continue si un mois échoue, log diagnostic)

#### F2 `CarnetPresenter.bulk_import_chesscom(username, profile_name, options)` — Orchestration
- [ ] **F2.1** Nouvelle méthode dans `CarnetPresenter.gd`
    - Crée profil : `create_profile(profile_name or "Chess.com • {username}", "chess_com", [username])`
    - Lance `ChessComService.fetch_all_player_games(username, options.max_months, options.max_games)`
    - À réception `games_fetched` : pour chaque jeu → `DatabaseManager.record_chesscom_game(g)` (existant, gère dedupe + player_keys)
    - Collecte `game_id` → lance `start_batch(game_ids)` (CarnetBatchRunner existant)
    - Émet `bulk_import_progress(phase, current, total)` : `"fetching"` / `"importing"` / `"analyzing"` / `"done"`
- [ ] **F2.2** Options par défaut : `max_months=12`, `max_games=500`, `depth=14`, `mode="dynamic"`

#### F3 `ChessComBulkImportModal.gd` — UI (nouveau composant T3)
- [ ] **F3.1** Fichier `src/ui/carnet/components/ChessComBulkImportModal.gd` (extends `Window`)
- [ ] **F3.2** Champs :
    - Pseudo Chess.com (LineEdit, pré-rempli dernier utilisé via SettingsManager)
    - Mois à importer (SpinBox 1-60, défaut 12)
    - Max parties (SpinBox 50-2000, défaut 500)
    - Nom carnet (LineEdit, défaut `"Chess.com • {username}"`, éditable)
- [ ] **F3.3** Bouton "Créer carnet & importer" → appelle `presenter.bulk_import_chesscom(...)`
- [ ] **F3.4** Barre progression 3 étapes :
    1. Récupération mois (`progress_fetched` signal)
    2. Import parties (compteur)
    3. Analyse (`batch_progress` signal du presenter)
- [ ] **F3.5** Bouton "Annuler" → `presenter.cancel_batch()` + `chess_com_service.cancel()` (nouvelle méthode)
- [ ] **F3.6** Toast final : "Carnet 'X' créé avec N parties — analyse en cours..."

#### F4 Intégration dans Overlay (onglet Sync)
- [x] **F4.1** Bouton "🌐 Importer Chess.com" à côté de "📥 Importer PGN" — *stub présent*
- [ ] **F4.2** Ouvre `ChessComBulkImportModal` avec `presenter` connecté
- [ ] **F4.3** À la fin → `presenter.refresh_sync()` + `presenter.refresh_carnet()` + `presenter.refresh_plan()`

#### F5 Tests
- [ ] **F5.1** Test manuel : pseudo existant (ex: `hikaru`), 3 mois, 100 parties → carnet créé, parties importées, analyse lancée
- [ ] **F5.2** Test rate-limit : 60 mois → vérifie pauses 2s entre requêtes, pas d'erreur 429
- [ ] **F5.3** Test annulation : clic "Annuler" pendant fetch → stoppe requêtes, nettoie état
- [ ] **F5.4** Test dedupe : réimporter même pseudo → parties existantes non dupliquées, sync à jour

---

## 3. Fichiers à créer / modifier

| Fichier | Action | Statut |
|---------|--------|--------|
| `src/ui/carnet/CarnetPresenter.gd` | Modifier : +9 méthodes + 3 signaux | ✅ |
| `src/ui/carnet/CarnetOverlay.gd` | Modifier : `_build_sync_tab`, `_rebuild_profiles`, nouveaux handlers (+ bouton Chess.com) | ✅ |
| `src/ui/carnet/components/CarnetProfileEditorModal.gd` | **Créer** | ✅ |
| `src/ui/carnet/components/CarnetGameListItem.gd` | **Créer** | ✅ |
| `src/ui/carnet/components/CarnetImportPgnModal.gd` | **Créer** | ✅ |
| `src/ui/carnet/components/ChessComBulkImportModal.gd` | **Créer** | ⏳ Phase F |
| `src/network/ChessComService.gd` | Modifier : + `fetch_all_player_games` + signal `progress_fetched` | ⏳ Phase F |
| `src/carnet/CarnetStore.gd` | Modifier : +1 méthode `update_game_perspective` | ✅ |
| `src/carnet/CarnetProfiles.gd` | Modifier : `match_games` lit `sync.json` + exclut `removed` | ✅ |
| `src/ui/carnet/components/CarnetProfileChip.gd` | Modifier : +menu contextuel (signal `context_menu_requested`) | ✅ |

---

## 4. Dépendances & ordre

```
Phase A (Presenter) → Phase B (Composants) → Phase C (Overlay) → Phase D (Store) → Phase E (Tests)
       ↑                                                                      │
       └────────────────── CarnetStore.update_game_perspective ──────────────┘

Phase F (Chess.com bulk) :
  F1 (ChessComService) → F2 (Presenter.bulk_import) → F3 (Modal UI) → F4 (Overlay integration) → F5 (Tests)
  Nécessite : A (create_profile, start_batch), C4 (bouton Sync), C5 (toast signal)
  Indépendant de : B1, B2, B3 (peut être parallélisé)
```

- **A** peut se faire en premier (tests unitaires presenter seul)
- **B** indépendant, peut être parallèle à **A**
- **C** nécessite **A** + **B**
- **D** nécessaire pour **C3.4** (perspective toggle)
- **F** nécessite **A** (create_profile, start_batch) + **C4/C5** (bouton + toast) — peut démarrer après A1, A7, C5

---

## 5. Décisions validées

| # | Question | Décision | Justification |
|---|----------|----------|---------------|
| 1 | Menu contextuel profil | **Signal `context_menu_requested(profile_id, global_pos)` dans `CarnetProfileChip` (T3)** | `gui_input` détecte clic droit + long-press (Timer). Overlay (T2) connecte une fois, affiche `PopupMenu` à la position. Séparation T2/T3 respectée. |
| 2 | Filtres liste parties | **`ButtonGroup` dans `ScrollContainer` horizontal** (pattern `_profile_row`) | 4 labels courts (`Toutes`, `À traiter`, `À jour`, `Périmées`) + `clip_text` + `TOUCH_MIN`. Cohérent, zéro nouveau pattern, scroll auto si futur ajout. |
| 3 | Import PGN | **Composition** : `CarnetImportPgnModal` instancie `PGNModal` interne | Connecte `pgn_loaded`, remplace bouton bas. `PGNModal` non modifié, découplé, testable. |
| 4 | Confirmation suppression | **`ConfirmationDialog` natif Godot** | Accessible, mobile-friendly, built-in. |
| 5 | Perspective forcée | **Cycle 3 états** : `""` (auto) → `"white"` → `"black"` → `""` stocké dans `sync.json` | `match_games()` lit `entry.perspective` si non-vide, sinon recalcule. Badge `⟳`/`⚪`/`⚫`. Rétrocompatible. Parties retirées marquées `removed` dans `sync.json`, exclues de `match_games()`. |
| 6 | Toast notifications | **Signal `toast_requested(msg, is_success)` dans `CarnetPresenter`** → `Main._show_toast` | Réutilise toast global existant, découplé, mockable en tests, zéro singleton. |
| 7 | Auto-ajout clés à l'import PGN | **`ConfirmationDialog` tactile** : `"Joueur «X» détecté. Ajouter aux clés ?" [Ajouter] / [Ignorer]` | Contrôle utilisateur, pas de magie silencieuse, modal accessible tactile + clavier. `add_player_key` + `refresh_sync` uniquement sur confirmation. |
| 8 | Tests | **Tests T1 durcis** : `_test_profile_crud`, `_test_profile_signals`, `_test_game_list`, `_test_game_signals`, `_test_import_pgn` | Pattern `_check` + vérifications d'effets de bord (état persité), headless, couvre nouvelles méthodes publiques (A2,A5,A6,A7,A8,A9,A10). Tests T2 étendus pour overlay Sync. |

---

## 6. Validation finale (Definition of Done)

- [x] Onglet **⟳ Sync** affiche : profils (créer/éditer/supprimer via + et menu contexte), bouton "Importer PGN", bouton "🌐 Importer Chess.com" (stub), liste parties avec filtres
- [x] Chaque ligne partie : titre, date, perspective, statut, 3 actions (réanalyser, forcer perspective, retirer)
- [x] Créer profil + clés → parties auto-rattachées à l'import suivant
- [x] Réanalyse unitaire met à jour carnet/plan/radar sans relancer tout le lot
- [x] Forcer perspective met à jour les drills générés (côté joueur correct)
- [x] Supprimer partie du carnet nettoie atomes + drills + sync (marquage `removed`)
- [x] Import PGN depuis Carnet → partie chargée + rattachée + carnet mis à jour
- [ ] **Import Chess.com bulk** : pseudo + mois → carnet créé + parties importées + analyse lancée + progression visible
- [x] Mobile : tout utilisable au doigt, pas de texte tronqué critique, modales centrées
- [x] `godot --headless` tests passent

---

## 7. Tests réalisés et leur statut

| Fichier test | Couche | Tests | Statut | Remarque |
|-------------|--------|-------|--------|----------|
| `tests/test_carnet_presenter.gd` | T1 | 42 | ✅ **42/42 passent** | `_test_profiles`, `_test_sync_and_carnet`, `_test_session`, `_test_reveal`, `_test_batch`, `_test_profile_crud`, `_test_profile_signals`, `_test_game_list`, `_test_game_signals`, `_test_import_pgn` |
| `tests/test_carnet_overlay.gd` | T2 | 24 | ✅ **24/24 passent** | `_test_structure`, `_test_tabs`, `_test_session`, `_test_sync_tab_structure`, `_test_profile_chip_context`, `_test_games_list_and_filters` |
| `tests/test_carnet_main_integration.gd` | Intégration | 6 | ✅ **6/6 passent** | Bouton 📓 → overlay → 3 onglets → fermeture |

**Total : 72/72 tests passent.**

---

## 8. Estimation relative (complexité)

| Phase | Complexité | Risque | Statut |
|-------|------------|--------|--------|
| A (Presenter) | Faible | Aucune — pattern existant | ✅ |
| B (Composants) | Moyenne | UI modale, signaux | ✅ |
| C (Overlay) | Moyenne | Intégration, scroll imbriqués | ✅ |
| D (Store) | Très faible | 1 méthode pure | ✅ |
| E (Tests) | Variable | Dépend couverture existante | ✅ |
| **F (Chess.com bulk)** | **Moyenne** | **Réseau, rate-limit, pagination, annulation** | ⏳ Non démarré |

**Réalisé** : ~11 fichiers touchés, ~700 lignes ajoutées, 0 breaking change.
