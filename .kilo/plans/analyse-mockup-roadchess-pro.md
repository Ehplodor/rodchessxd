# LeChess — thèse produit, architecture modulaire et différenciation

> Document de travail (plan, non implémenté). Suite de l'analyse du mockup « RoadChess Pro ».
> Objectif : séparer le **table stakes** (commodité) du **différenciant**, définir une suite de modules
> cohérente, et trancher les choix techniques (dont l'**inférence locale SLM**).
> Contexte : Godot, portrait, 100 % local, IA BYOK + SLM local, OCR embarqué, Stockfish, Maia.
>
> Nomenclature proposée : **LeChess** (application) — modules **LeCarnet**, **LeCoach**, **LeLive!**, **LeArena**.

---

## 1. Constat : le mockup est une carte de commodités

| Brique de la maquette | Qui le fait déjà | Verdict |
| --- | --- | --- |
| Analyse moteur + ACPL + précision + ELO | chess.com, Lichess | commodité |
| Graphe d'éval, flèches, coups clés, multi-PV | Lichess, chess.com | commodité |
| Game Review « 1 ligne par coup » | chess.com | commodité |
| Ouvertures / explorer / base de données | Lichess, chess.com, Chessable | commodité |
| Énigmes / puzzles | Lichess (gratuit, immense) | commodité |
| Entraînement personnalisé depuis tes parties | **Aimchess** | différenciant — déjà pris, mais en cloud |
| Répétition espacée de répertoires | **Chessable** | différenciant — déjà pris |
| Cours & vidéos | chess.com, Chessable | guerre de contenu perdue |
| Jouer en ligne / tournois / communauté | Lichess (gratuit), chess.com | effets de réseau déjà gagnés |
| **Tournois entre LLM** | quasi personne | **terra incognita** |

**3 actifs structurels que RodChessXD possède déjà et que les géants ne peuvent pas copier sans se cannibaliser :**
1. **100 % local / zéro compte** (offline, aucune donnée exfiltrée).
2. **IA model-agnostic + SLM local** (l'utilisateur choisit son « cerveau », son coût, sa vie privée).
3. **Vision OTB embarquée** (OCR pur GDScript) → pont échiquier physique ↔ coach.

---

## 2. Anti-roadmap (ce que l'on ne construit PAS)

| À ne PAS construire | Pourquoi |
| --- | --- |
| Jouer en ligne / Tournois humains / Communauté | backend + anti-triche + masse critique ; Lichess le fait gratuitement |
| Cours & Vidéos | coût de contenu permanent, concurrence Chessable/chess.com |
| Comptes cloud / profils publics / fil social | contredit l'ADN local/privé |
| Échiquier 3D | gadget, coût perf, zéro rétention |
| Devenir un « hub de contenu » | LeChess est un **coach**, pas un média |

> **Exception** : les **tournois entre LLM (LeArena)** ne sont ni un clone de chess.com ni du matchmaking humain —
> c'est du contenu généré par l'app, sans backend social, et hautement viral. Dans le périmètre.

---

## 3. La suite modulaire LeChess

```
        ┌────────────────────────────────────────────────────────────┐
        │                        LeChess (app)                        │
        └───────┬───────────────┬───────────────┬────────────────────┘
                │               │               │
        ┌───────▼──────┐ ┌──────▼───────┐ ┌─────▼────────┐ ┌──────────────┐
        │  LeCarnet    │ │  LeCoach     │ │  LeLive!     │ │  LeArena     │
        │ 100% algo    │ │ LLM+Stockfish│ │ LLM commente │ │ LLM vs LLM   │
        │ (aucun LLM)  │ │  tool-use    │ │ (événements) │ │ + arbitre    │
        └───────┬──────┘ └──────┬───────┘ └─────┬────────┘ └──────┬───────┘
                │               │               │                 │
        ┌───────▼───────────────▼───────────────▼─────────────────▼───────┐
        │  Socle local : ChessGame (règles) · EngineManager (Stockfish)    │
        │  · MoveQualityService · GameAnalyzer · OpeningBook               │
        │  · AICoach (providers) · DatabaseManager · ChessOCR              │
        │  · Runtime LLM local : llama.cpp (voir §9)                       │
        └──────────────────────────────────────────────────────────────────┘
        Maia = uniquement adversaire de sparring (jeu), jamais le « cerveau » du coach.
```

**Règle de séparation :** LeCarnet **détecte** (déterministe), LeCoach/LeLive! **racontent** (génératif),
le moteur **vérifie**, `ChessGame` **arbitre**. Aucun LLM n'est jamais la source de vérité.

---

## 4. Module 1 — **LeCarnet** (100 % algorithmique) — spécification complète

> **But.** Transformer automatiquement les parties du joueur en un **carnet de moments** — fautes **et**
> bons coups, **et** moments de **surprise** et de **mystère** — puis en un **plan d'entraînement
> quotidien**, **sans aucune IA générative** : uniquement des statistiques déterministes calculées sur des
> données déjà produites par le moteur. Rejouable à l'identique, hors-ligne, gratuit, sans réseau.
>
> **Double usage.** Le Carnet n'est pas seulement un outil d'entraînement : c'est aussi le **détecteur
> d'événements** que **LeLive!** consomme pour commenter une partie (la tienne, ou un match de **LeArena**),
> y compris les coups brillants, les surprises et les retournements — pas seulement les erreurs.
>
> **Exigence de ce chapitre :** l'algorithme doit être entièrement exprimé en langage naturel **avant**
> toute ligne de code — à la lecture seule, on doit comprendre exactement ce que l'app calcule, stocke,
> affiche et propose chaque jour.

### 4.0 Principe en une phrase
LeCarnet **détecte et classe des événements notables** dans chaque partie — erreurs, **bons coups**,
**brillances**, **surprises** et **positions mystérieuses** — en déduit des **motifs** (faiblesses **et**
forces) notés et pondérés par la **confiance**, en tire des **exercices** construits sur ses **propres
positions**, et les ressert selon un **calendrier de répétition espacée** — le tout déterministe.

### 4.0bis Architecture en trois étages (le cœur du module)

```
ENTRÉES BRUTES           ÉTAGE 1 — ATOMES            ÉTAGE 2 — COMPILATION            ÉTAGE 3 — RENFORCEMENT
(réutilisable live)      (par coup · sans état)      (multi-parties · temporel)       (pédagogie · purement algo)
──────────────────       ───────────────────         ─────────────────────────        ──────────────────────────
Stockfish : cp/mat   ─┐  • normalisation win%     ─┐  • motifs faiblesses / forces ─┐  • modèle de compétence
MultiPV, PV          │  • features contextuelles   │  • compétences par dimension   │  • écart théorie ↔ pratique
FEN avant / après    ├─►  (matériel, phase,        ├─► • tendances temporelles       ├─► • scheduler (SM-2 + interleaving,
Book / ECO           │    structure, théorie,      │  • profil (radar)              │    difficulté désirable, variation)
Horloge              │    naturalité, criticité)   │  • chronologie « moments forts »│  • équilibrage forces/faiblesses
Règles (ChessGame)  ─┘  • indices IS / IM         ─┘  • théorie vs pratique ─────────┘  • LePlan (objectif du jour)
                        • polarité & catégorie                                                   • détection de plateau
                        ▲ CarnetEvents                        ▲ CarnetLedger                     ▲ CarnetTrainer
                        └──────────── consommé en direct par LeLive! & LeArena ───────────┘
```

| Étage | Composant | Portée | Rôle en une phrase | Étapes |
| --- | --- | --- | --- | --- |
| **1** | `CarnetEvents` | le coup | transformer le signal brut du moteur en **atomes** normalisés, étiquetés et notés (IS/IM) | §4.3 · §4.4 · §4.4.1 · §4.4.2 |
| **2** | `CarnetLedger` | la partie et l'historique | **compiler** les atomes dans le temps et selon plusieurs **dimensions** → faiblesses, forces, compétences, écarts | §4.5 · §4.6 · §4.7 · §4.0ter |
| **3** | `CarnetTrainer` | le plan et la progression | **décider** quoi entraîner, quand et comment (renforcer/atténuer), sans LLM | §4.8 → §4.11 |

**Pourquoi trois étages (et pas un seul) :**
- **Séparer le constat, la connaissance et la décision.** L'étage 1 ne sait rien du joueur ; l'étage 2 ne
  décide de rien ; l'étage 3 ne mesure rien lui-même. Chaque étage est **testable et remplaçable** isolément.
- **Réutilisable en direct.** L'étage 1 est **sans état** : LeLive! et LeArena l'appellent sans jamais
  toucher au carnet d'entraînement du joueur.
- **Déterminisme total.** À chaque étage, les sorties sont des fonctions pures de leurs entrées (et de la date).

### 4.0ter Les dimensions d'agrégation (axes réfléchis)

**Étage 1 — dimensions « signal » (par coup)** : le premier étage agrège plusieurs mesures brutes en un atome
en les rapportant à des axes choisis pour être **stables et comparables** :
1. **évaluation** (win%, delta, volatilité, distance au mat) ;
2. **qualité** (taxonomie win%-based) ;
3. **matériel** (balance, sacrifice, type d'échange) ;
4. **position** (phase, structure de pions, sécurité du roi, activité) ;
5. **tactique** (coups forcés, unicité, gain matériel de la PV) ;
6. **théorie** (dans/hors livre, ECO, nouveauté) ;
7. **naturalité** (évident / non évident) ;
8. **temps** (ply, horloge restante, temps de réflexion) ;
9. **criticité** (tension, chemin étroit) ;
10. **surprise / mystère** (`IS`, `IM`).

**Étage 2 — dimensions « apprentissage » (agrégation multi-parties)** : le deuxième étage compile les atomes
sur ces axes, chacun avec sa propre fenêtre temporelle et son propre filtre de confiance :
1. **temporelle** (récence, fenêtre glissante, tendance) ;
2. **phase** (ouverture / milieu / finale, + type de finale) ;
3. **couleur** (blancs / noirs) ;
4. **matériel & structure** (équilibré, déséquilibré, structure de pions) ;
5. **registre** (tactique vs positionnel) ;
6. **ouverture / ECO** (lignes réellement mal jouées) ;
7. **contexte de résultat** (en avance / égal / en retard ; conversion vs récupération) ;
8. **adversaire** (tranche d'Elo rencontrée) ;
9. **cadence / temps** (blitz vs classique) ;
10. **théorie ↔ pratique** (ce qui est **connu** vs ce qui est **appliqué** en conditions réelles).

> **Principe de prudence :** une dimension n'est agrégée que si son échantillon est suffisant ; chaque résultat
> porte sa **confiance** (§4.6) et une dimension vide ne produit jamais d'affirmation.

> Cette séparation rend le Commentaire Live (`LeLive!`) et l'entraînement (`LePlan`) **réutilisables
> séparément** : un match LeArena utilise l'étage 1 sans rien stocker dans le carnet du joueur.

### 4.1 Vocabulaire à figer avant de coder
| Terme | Définition | Persistance |
| --- | --- | --- |
| **Partie** | une partie analysée du joueur | `user://library/…` |
| **Coup candidat** | un demi-coup ayant une évaluation moteur | dérivé |
| **Atome** (= événement notable) | sortie de l'**étage 1** : un coup candidat + features contextuelles + polarité + catégorie + `IS`/`IM`, au-dessus des seuils | recalculable, clé `event_id` |
| **Compilation** | sortie de l'**étage 2** : agrégation temporelle et multi-dimensionnelle des atomes (motifs, compétences, tendances) | recalculable |
| **Polarité** | `négatif` (à corriger) · `positif` (force) · `curieux` (surprise/mystère) | fixe |
| **Dimension** | axe d'agrégation réfléchi (§4.0ter), stable et comparable dans le temps | fixe |
| **Motif** | couple `(famille, clé)` — ex. `(phase, finale)`, `(schéma, sacrifice)`, `(ouverture, B90)` | recalculable |
| **Faiblesse / Force** | un motif (négatif / positif) avec assez d'atomes **et** de confiance pour être affirmé | affiché |
| **Compétence** | note 0–100 d'une dimension d'apprentissage, **avec confiance** (étage 3) | recalculable |
| **Écart théorie ↔ pratique** | différence entre compétence mesurée en drills (« connu ») et en partie réelle (« appliqué ») | calculé |
| **Preuve** | un atome montré à l'utilisateur (position avant + coup joué + meilleur coup) | cliquable |
| **Drill** | exercice généré depuis une preuve — **corriger** une faiblesse **ou trouver** une brillance/mystère | planifiable |
| **Maîtrise** | motif sans nouvel atome négatif sur une fenêtre récente **et** drills réussis | archivé/monitoré |

**Invariant :** le Carnet est une **fonction pure** de `(événements stockés, date du jour, graine)`. Aucun
hasard non seedé, aucun appel LLM, aucun accès réseau.

### 4.2 Entrées exactes (rien d'autre n'est lu)

**Par partie :** `game_id`, `date` (date locale, stockée ISO), `couleur_joueur` (blancs/noirs), `résultat`,
`source`, `cadence` (si connue), `elo_estime`, `eco`, `nom_ouverture`, `nombre_de_plies`, `issue`
(abandon/forfait → partie ignorée si < 10 plies).

**Par coup candidat (déjà calculé par `GameAnalyzer` / `MoveQualityService`) :** `ply`, `san`, `uci`,
`pièce`, `qualité` (BEST…MISS), `cp_loss`, `perte_winpct`, `eval_avant`/`eval_après` (cp/mat),
`meilleur_coup_uci`, `coup_alt_uci`, `pv`, `fen_avant`, `fen_après`, `phase`, `dans_la_théorie`.
**Dérivés (déterministes depuis `fen_avant`) :** balance matérielle, type de finale, sécurité du roi,
droits de roque, structure de pions.

### 4.3 Étage 1 · A — Détection des atomes (toutes polarités)
On examine **chaque** coup candidat et on le range dans l'une de trois polarités ; la grande majorité des
coups ne produit **rien** et est ignorée silencieusement.

**A.1 — Événement NÉGATIF (faute)** si **toutes** ces conditions sont vraies :
1. c'est un coup du **joueur** (selon `couleur_joueur`) ;
2. sa qualité ∈ { `IMPRECISION`, `ERREUR`, `GAFFE`, `OCCASION_MANQUÉE` } ;
3. `perte_winpct ≥ 10` (seuil `WINPCT_INACCURACY`) ;
4. il **n'est pas** un coup de théorie (`dans_la_théorie = faux`) ;
5. le joueur avait **plus d'un** coup légal (un coup forcé n'est pas une faute) ;
6. la partie compte ≥ 10 plies.
Sa **gravité** est `s(f) = min(perte_winpct / 40, 1)` (≥ 40 points de win% = gravité maximale).

**A.2 — Événement POSITIF (bon coup / brillance)** si :
1. c'est un coup du **joueur** (ou, en mode analyse/diffusion, de n'importe quel joueur) ;
2. sa qualité ∈ { `BEST`, `GREAT`, `BRILLIANT`, `EXCELLENT` } ;
3. **et** au moins un **marqueur d'excellence** est réuni (voir §4.4.1) : sacrifice, coup unique,
   trouvaille profonde, ressource défensive, précision critique.

**A.3 — Événement CURIEUX (surprise / mystère)** si l'un des indices correspondants dépasse son seuil
(voir §4.4.2), **même sur un coup par ailleurs correct** : coup inattendu mais bon, nouveauté théorique,
renversement, position à haute instabilité.

> Pourquoi la perte en **win%** et non en centipions : perdre 200 cp dans une position déjà gagnante n'est
> pas la même faute que les perdre dans une position égale. La win% intègre déjà ce contexte.

`event_id = SHA1(game_id + ":" + ply + ":" + couleur_joueur)` → **idempotence** et dédoublonnage (l'identité
du coup est stable ; polarité et indices sont recalculables).

### 4.4 Étage 1 · B — Étiquetage : les 9 familles de motifs
Chaque fait reçoit **une clé par famille** (la famille « schéma » peut en recevoir plusieurs).

| # | Famille | Clés possibles | Règle de calcul |
| --- | --- | --- | --- |
| 1 | **Phase** | `ouverture` / `milieu` / `finale` | fourni par `GamePhaseService` |
| 2 | **Qualité** | `imprécision` / `erreur` / `gaffe` / `occasion_manquée` | fourni par la taxonomie |
| 3 | **Régime** (avant le coup) | `en_avance` (win% ≥ 70) / `équilibré` (30–70) / `en_retard` (≤ 30) | calculé sur `eval_avant` |
| 4 | **Pièce bougée** | `P` / `C` / `F` / `T` / `D` / `R` | depuis `fen_avant` + `uci` |
| 5 | **Ouverture** | code `ECO` + nom | attribué si `ply ≤ ply_sortie_théorie + 6`, sinon `sortie_de_théorie` |
| 6 | **Type de finale** | `aucune` / `tours` / `pions` / `mineures` / `dames` / `mixte` | classifieur matériel déterministe, seulement si phase = finale |
| 7 | **Schéma** (multi-label) | voir liste ci-dessous | règles explicites, aucune heuristique floue |
| 8 | **Tranche de coups** | `1–10` / `11–20` / `21–30` / `31–40` / `41+` | depuis `ply` |
| 9 | **Temps** (si horloge PGN disponible) | `pression_temps` | vrai si temps restant ≤ 10 % du temps initial |

**Clés de la famille « Schéma » (déterministes, calculables depuis `fen` + PV moteur) :**
- `piece_en_prise` : après le coup joué, le meilleur coup adverse gagne ≥ 2 pions de matériel.
- `capture_ratée` : le meilleur coup était une capture gagnante, le joueur n'a pas capturé.
- `echec_manqué` : le meilleur coup donnait échec ou mat, le joueur n'a pas donné échec.
- `gain_tactique_manqué` : le meilleur coup force un gain matériel ≥ 2 pions dans la PV.
- `dame_sortie_tôt` : coup de dame au ply ≤ 20 avant que toutes les pièces mineures soient développées.
- `sécurité_roi` : faute alors que le roi n'est pas roqué et que l'adversaire a des attaquants, **ou** poussée de pion devant le roi.
- `structure_pions` : poussée de pion créant un pion doublé / isolé / arriéré (détection déterministe).
- `roi_non_roqué` : le joueur a perdu ses droits de roque sans avoir roqué au 12ᵉ coup.
- `pression_temps` : faute avec très peu de temps (uniquement si horloge disponible).

> **Bornes volontaires :** LeCarnet **ne nomme pas** les motifs tactiques fins (fourchette, enfilade,
> clouage) — il dit « gain tactique manqué / pièce en prise ». Nommer ces motifs est une extension v2.

### 4.4.1 Le versant positif — bons coups, brillances, forces
On ne commente pas que les erreurs : un carnet qui ne retient que le négatif démoralise et rate l'essentiel
du spectacle. On détecte donc des **marqueurs d'excellence** déterministes :

| Marqueur | Définition algorithmique |
| --- | --- |
| `sacrifice` | la balance matérielle du joueur **baisse de ≥ 2 pions** au coup joué, et `eval_après` ne se dégrade pas au-delà de `SAC_TOL` (≈ −0,5 pion) ou reste gagnante. Sous-types : échange/qualité, gambit d'ouverture, sacrifice positionnel. |
| `coup_unique` | dans le MultiPV, le meilleur coup préserve le résultat et le **2ᵉ meilleur perd ≥ 15 win%** (`ONLY_MOVE_WINPCT`) → « seul coup ». |
| `trouvaille_profonde` | le coup n'est **pas** dans le top 3 d'une recherche **peu profonde** (~profondeur 8) mais est le meilleur en profondeur → « invisible à l'œil nu ». Si la passe peu profonde n'est pas faite : marqueur = 0 (aucune fausse affirmation). |
| `ressource_défensive` | en position perdante (win% ≤ 30), coup **unique** qui remonte la win% de ≥ 15 points → le sauvetage. |
| `précision_critique` | position équilibrée (30–70) où **toutes** les alternatives perdent ≥ 15 win% et où le coup joué est le meilleur → le coup qu'il fallait trouver. |

**Catégorie positive** attribuée (déterministe) : `brillant` (BRILLIANT/GREAT + sacrifice ou seul coup
tranchant) · `trouvaille` (trouvaille profonde / ressource défensive / coup unique) · `précis`
(précision critique) · `bon` (meilleur coup ordinaire).

**Forces (motifs positifs).** Les événements positifs s'agrègent avec **la même machinerie** que les
faiblesses (§4.5), mais la « gravité » devient un **mérite** :
`m(e) = 0,5·niveau_brillance + 0,3·(IS/100) + 0,2·importance_de_la_position` (importance = criticité de la
position, cf. `tension`). On obtient un classement « **Tes forces** » (ex. « tu excelles dans les finales de
tours », « tu trouves les sacrifices »). Les forces ne génèrent pas de drills de correction mais des
**drills de maintien / défi** (§4.8).

### 4.4.2 Surprise & Mystère — définitions algorithmiques
Deux notions distinctes, souvent confondues, à formaliser séparément :

- **La Surprise est un événement** : l'**écart entre l'attendu et le réel**. Elle se mesure **par coup**.
- **Le Mystère est un état** : l'**imprévisibilité d'une position**. Elle se mesure **avant le coup**.

**Sources de surprise** (toutes calculables, hors-ligne) :
1. `écart_naturalité` — le coup est **non évident** : coup calme, retrait, coup intermédiaire (Zwischenzug),
   marche du roi ; à l'opposé, capture/reprise/échec/mat/roque/promotion = évident. *Un bon coup évident
   n'est pas une surprise.*
2. `sacrifice` — du matériel est donné (cf. §4.4.1).
3. `unicité` — le coup est le **seul** à tenir (ou à gagner).
4. `profondeur` — le coup est introuvable à faible profondeur (trouvaille profonde).
5. `nouveauté` — le coup **sort du livre** (via `OpeningBook`) tout en restant bon → nouveauté théorique.
6. `volatilité` — le coup provoque un **grand saut** de win%, **mais seulement si la position était
   équilibrée avant** (sinon un gain déjà acquis n'étonne personne).

**Indice de Surprise (IS ∈ [0,100])** :
```
IS = 100 × ( 0,25·écart_naturalité + 0,20·sacrifice + 0,20·unicité
           + 0,15·profondeur + 0,10·nouveauté + 0,10·volatilité )
```
avec `unicité = min(écart_winpct_2e / 20 ; 1)` et `volatilité = min(|Δwinpct| / 30 ; 1)` si la position
était équilibrée (25–75 win%), sinon 0.

**Sources de mystère** (propriétés de la position **avant** le coup) :
1. `instabilité` — l'évaluation bouge selon la profondeur/les lignes : `min(écart_winpct_inter-profondeurs / 25 ; 1)`.
2. `pluralité` — **beaucoup** de coups se valent (MultiPV serré) : « jungle de possibilités » ;
   `min((nb_coups_à_moins_de_5_winpct_du_meilleur − 1) / 5 ; 1)`.
3. `compensation` — **déséquilibre matériel ≥ 2 pions** alors que l'éval reste serrée (|eval| ≤ 1 pion) :
   personne ne sait qui est mieux ; `min(|déséquilibre| / 4 ; 1)`.
4. `tension` — à l'inverse de la pluralité : **chemin étroit**, un seul (ou aucun) coup conserve le
   résultat → le « fil du rasoir ».

**Indice de Mystère (IM ∈ [0,100])** :
```
IM = 100 × ( 0,35·instabilité + 0,25·pluralité + 0,20·compensation + 0,20·tension )
```
> Le mystère a donc **deux saveurs** : la *jungle* (pluralité/instabilité : trop de chemins flous) et le
> *fil du rasoir* (tension : un seul chemin). Toutes deux valent d'être commentées.

**Décision** : un événement devient `surprise` si **IS ≥ 60** (`IS_SURPRISE`) et `mystère` si **IM ≥ 65**
(`IM_MYSTERE`) ; un même coup peut être les deux. En cas de données insuffisantes (pas de MultiPV, pas de
passe peu profonde), les composantes concernées valent **0** : aucune surprise n'est jamais inventée.

### 4.4.3 Réutilisation hors entraînement — LeLive! & LeArena (interface explicite)
`CarnetEvents` étant **sans état**, il s'appelle dans n'importe quel contexte :

```
CarnetEvents.annotate(coup) -> Annotation {
    event_id, polarité, catégorie, IS, IM,
    marqueurs { sacrifice, coup_unique, profondeur, nouveauté, ... },
    indices   { instabilité, pluralité, compensation, tension },
    position_avant, coup_joué, meilleur_coup, pv
}
```

**Qui fournit les évaluations** :
- **Partie normale (LeLive! Live)** : `GameController` → `EngineManager.evaluate_position` par coup (déjà en
  place) ; l'annotation consomme ces données. L'**analyse en direct du moteur** (barre d'éval) et LeLive!
  restent **indépendants** : l'un affiche la vérité chiffrée, l'autre la raconte.
- **Match LeArena** : l'**Arbitre** (`ArenaRunner`) évalue chaque position avec Stockfish **pour lui-même**,
  *indépendamment des outils autorisés aux joueurs*. En mode **Classique** (LLM sans moteur), les joueurs
  n'ont pas accès au moteur — mais **le public reçoit quand même le commentaire**, car l'arbitre évalue.

**Consommation par LeLive!** : à chaque ply, LeLive! ne parle que si l'annotation dépasse un seuil
(faute grave, `brillant`, `trouvaille`, `surprise`, `mystère`, ou renversement d'éval). Deux usages :
1. **Live** — ma partie, commentée en direct (coups forts *et* faibles).
2. **Diffusion** — une partie importée **ou un match LeArena**, commenté à la manière d'un broadcast.

**Stockage** : les événements d'un match LeArena **ne polluent pas** le carnet d'entraînement du joueur ;
ils alimentent un store séparé (replay, « tableau des moments forts »). Option explicite : « ajouter cette
partie à mon carnet » (utile pour analyser sa propre performance contre un LLM).

### 4.5 Étage 2 · C — Score d'un motif (faiblesse **ou** force)
La même formule sert aux deux polarités : pour une **faiblesse**, `s(e)` est la **gravité** (perte de win%) ;
pour une **force**, `s(e)` est le **mérite** défini en §4.4.1. Pour un motif `m` et ses événements `E_m` :

1. **Occurrences** : `n_m = |E_m|`.
2. **Poids de récence** d'un événement : `w(e) = 0,5 ^ (âge_jours(e) / 45)` (45 jours compte moitié).
3. **Gravité/mérite moyen pondéré** : `S_m = Σ_e w(e)·s(e) / Σ_e w(e)` (∈ [0,1]).
4. **Fréquence par partie** : `P_m = n_m / G`, où `G` = nombre de parties du joueur analysées.
5. **Confiance (retenue bayésienne)** : `K_m = n_m / (n_m + 4)` → 4 occurrences ⇒ 0,50 ; 12 ⇒ 0,75.
6. **Score final** : `Score_m = 100 × K_m × ( 0,6 × S_m + 0,4 × min(P_m / 0,5, 1) )`, borné [0, 100].

**Interprétation lisible :** *« à quel point c'est grave/méritoire quand ça arrive » (60 %)* + *« à quelle
fréquence par partie » (40 %)*, le tout **freiné par le manque de données** `K_m`. Un motif vu 1 fois ne peut
donc jamais dominer le carnet.

### 4.6 Étage 2 · D — Filtrage, confiance, non-redondance
- **Motif émergent** : `n_m ∈ {1, 2}` → affiché en « pistes à confirmer », jamais affirmé.
- **Faiblesse / Force établie** : `n_m ≥ 3` **et** `K_m ≥ 0,43` (mêmes seuils pour les deux polarités).
- **Non-redondance** : si un motif `m2` est **plus spécifique** que `m1` (l'ensemble `F_m2 ⊂ F_m1`) et que
  `|F_m2| ≥ 0,5 × |F_m1|`, on **conserve `m2`** et on rétrograde `m1` (visible seulement dans « tous les
  motifs »). Exemple : `(type_finale, tours)` retient l'attention plutôt que `(phase, finale)`.
- **Classement** : par `Score_m` décroissant ; égalité arbitrée par `n_m`, puis par ordre alphabétique de
  `(famille, clé)` (déterminisme total).

### 4.7 Étage 2 · E — Tendance (amélioration / aggravation) + compilation multi-dimensionnelle
- **Récent** = 20 dernières parties (`RECENT_GAMES`) ; **ancien** = le reste.
- `taux_récent = n_récent / G_récent` ; `taux_ancien = n_ancien / G_ancien`.
- Si `taux_récent ≤ 0,6 × taux_ancien` → **en amélioration**.
- Si `taux_récent ≥ 1,5 × taux_ancien` → **en aggravation**.
- Sinon → **stable**. (Si `G_ancien = 0` → indéterminé.)

**Compilation multi-dimensionnelle (étage 2).** Au-delà de la tendance globale, chaque **dimension** de
§4.0ter est compilée **séparément**, dans sa propre fenêtre : par phase, par couleur, par ouverture, par
registre tactique/positionnel, par tranche d'adversaire, par cadence… On obtient un **profil** (radar) où
chaque axe porte son score **et sa confiance**. Règles :
- une dimension n'apparaît que si `n ≥ MIN_N_ETABLIE` et `K ≥ 0,43` (§4.6) ;
- les dimensions se comparent **à échantillon comparable** (on n'oppose pas 30 blitz à 4 classiques) ;
- le profil expose les **contrastes** (« fort en tactique, faible en finale de tours ») plutôt qu'un score unique.

### 4.8 Étage 3 · F — Génération des drills (depuis TES positions)
Les drills naissent des **preuves**, quelle que soit leur polarité :

**Drills de correction** (faiblesses, priorité ~80 %) : pour chaque faiblesse établie, prendre ses preuves
triées par `(gravité s(f) ↓, âge ↑, event_id ↑)`, **au plus 4** (`DRILLS_PER_MOTIF`), un par événement
distinct. Types :
- `trouve_le_coup` : le meilleur coup est une capture, un échec/mat, ou force un gain ≥ 2 pions ;
- `choix_binaire` : sinon, on présente le meilleur coup **et** le coup joué, à départager.

**Drills positifs / de curiosité** (priorité ~20 %) : générés depuis les événements `brillant`,
`trouvaille`, `surprise` et `mystère` — **les meilleures énigmes sont les trouvailles** :
- `trouve_la_brillance` : rejoue la position et **trouve le sacrifice / le seul coup** (le plaisir de la
  découverte est un puissant moteur de rétention) ;
- `résous_le_mystère` : position à fort `IM` où l'on demande d'évaluer puis de trouver le meilleur coup ;
- ces drills ne « corrigent » rien : ils **consolident une force** et entretiennent la motivation.

Un drill contient : `position_avant`, la **réponse** = `meilleur_coup_uci`, le **piège** = `coup_joué`,
la PV de 3 plies, sa polarité et son motif d'appartenance.

**Vérification d'une réponse utilisateur (hors-ligne, algorithmique) :**
- acceptée si le coup joué **est** le meilleur coup ; sinon on interroge **Stockfish local** (déjà embarqué)
  et on accepte si la perte de win% par rapport au meilleur coup est ≤ 3 points (`WINPCT_TOL`) ;
- sinon refusée, avec affichage de la meilleure ligne. *(LeCarnet reste 100 % algorithmique : il utilise le
  moteur déterministe, jamais un LLM.)*

### 4.9 Étage 3 · G — Ordonnanceur de répétition espacée (SM-2 adapté)
Chaque drill porte : `EF` (facteur de facilité, init **2,5**), `intervalle_jours`, `répétitions`, `lapses`, `échéance`.
À chaque passage, l'utilisateur note **0–2 = échec**, **3 = difficile**, **4 = bien**, **5 = facile** :
- si note < 3 → `répétitions = 0`, `intervalle = 1 j`, `EF = max(1,3 ; EF − 0,2)`, `lapses += 1` ;
- si note ≥ 3 → `répétitions += 1` ; `intervalle = 1 j` (1ʳᵉ), `6 j` (2ᵉ), puis `round(intervalle_précédent × EF)` ;
  et `EF = borne(EF + (0,1 − (5−note)×(0,08 + (5−note)×0,02)) ; 1,3 ; 2,8)`.
- `échéance = aujourd'hui + intervalle`.

> Résultat : une position ratée revient vite, une position maîtrisée s'espace (1 j → 6 j → ~15 j → ~35 j…).

### 4.10 Étage 3 · H — **LePlan** : composition du plan du jour
1. **File due** = drills non maîtrisés dont `échéance ≤ aujourd'hui`, triés par `(Score du motif ↓,
   échéance ↑, gravité ↓, event_id ↑)`.
2. **Contraintes de variété** : au plus `MAX_PER_MOTIF = 2` drills du même motif, au plus **1** drill par
   partie, et **au moins 1** drill de « révision » ancienne (interleaving) si disponible.
3. **Taille de séance** : ≤ `SESSION_SIZE = 5`.
4. **Complément** : si la file due < 5, on ajoute des drills **neufs** des 3 meilleures faiblesses jamais
   encore travaillées, sous les mêmes contraintes.
5. **Équilibre des polarités** : environ **20 %** de la séance provient des drills **positifs/curiosité**
   (`trouve_la_brillance`, `résous_le_mystère`) — on ne termine jamais une séance sur une accumulation de
   fautes. Si un moment fort a marqué la dernière partie, il a priorité en fin de séance.
6. **Jour vide** : si rien n'est disponible → « jour de repos », ou proposition d'une **partie d'entraînement**
   contre Maia, ou révision libre.
7. **Déterminisme** : la sélection dépend de `(date du jour, pools ordonnés)`. Le bouton « Régénérer » utilise
   la graine suivante `(date + tentative)` → deux personnes le même jour ont le même plan ; un re-tirage reste reproductible.

### 4.11 Étage 3 · I — Renforcement / atténuation (algorithmes d'apprentissage)
L'étage 3 transforme la **connaissance** (étage 2) en **décisions d'apprentissage**. Purement algorithmique :
il ne rédige aucun texte, mais peut **demander** à LeCoach d'expliquer une leçon.

**A. Modèle de compétence (une note par dimension)**
- Chaque dimension `d` (§4.0ter) porte une **compétence** `Skill_d ∈ [0,100]` et une **confiance** `K_d`.
- **Élo de compétence** : chaque atome/drill a une **difficulté** `Dif` estimée par le moteur (écart à la
  2ᵉ meilleure ligne, présence d'un sacrifice, profondeur nécessaire, criticité). La réussite/l'échec met à jour :
  `P_succès = 1 / (1 + 10^((Dif − Skill_d)/400))`, puis `Skill_d ← Skill_d + k·(résultat − P_succès)`, `k ≈ 12`.
- **Unifie entraînement et parties** : un drill et une occurrence en partie réelle mettent à jour **la même**
  compétence — c'est ce qui rend la comparaison théorie ↔ pratique possible.

**B. Écart théorie ↔ pratique (le signal pédagogique clé)**
- On mesure la même compétence dans **deux contextes** : **théorie** (drills, positions déjà entraînées) et
  **pratique** (positions **nouvelles** rencontrées en partie).
- `Écart_d = Skill_théorie,d − Skill_pratique,d` → trois régimes :

  | Régime | Signature | Décision |
  | --- | --- | --- |
  | **Ne sait pas** | théorie et pratique basses | **enseigner** : drills guidés + explication (LeCoach) |
  | **Sait mais n'applique pas** | théorie haute, pratique basse (écart fort) | **transférer** : positions nouvelles, chrono, interleaving, mise en situation |
  | **Acquis** | les deux hauts, écart faible | **maintenir** : révisions espacées uniquement |

- Ce signal est **impossible** à obtenir par simple comptage de fautes : il distingue « la connaissance » de
  « l'exécution sous pression ».

**C. Scheduler d'apprentissage**
- **Répétition espacée** (SM-2, §4.9) + **interleaving** (alterner les motifs) + **difficulté désirable**
  (viser ~70–85 % de réussite : trop facile = pas d'apprentissage, trop dur = découragement) + **variation**
  (même motif, positions différentes → transfert).
- **Équilibrage forces/faiblesses** : le budget de séance va majoritairement aux faiblesses à fort score, mais
  réserve une part au **maintien des forces** (`POSITIVE_DRILL_RATIO`) et aux **écarts théorie↔pratique** les plus forts.
- **Rendements décroissants** : un motif proche de la maîtrise passe en **entretien** (révisions rares) plutôt
  qu'en bourrage ; on évite de sur-entraîner un seul motif.
- **Détection de plateau** : si `Skill_d` stagne sur `PLATEAU_SEANCES` (≈ 6) séances → **changer le format**
  (autre difficulté, autre contexte, autre dimension) avant de persévérer.
- **Sortie** : `LePlan` (§4.10) est la **traduction quotidienne** de ce scheduler — chaque drill du jour est
  justifié par un objectif de compétence, pas seulement par une échéance SM-2.

**D. Progression, maîtrise, archivage (mesures visibles)**
- **Le score d'une faiblesse est recalculé à chaque nouvelle partie** : si le joueur cesse de commettre le
  motif en conditions réelles, `P_m` puis `Score_m` baissent → **preuve de progrès visible**.
- **Indice de Progression global** : `100 − moyenne des Scores des 5 faiblesses les plus fortes`
  (100 s'il n'y a aucune faiblesse établie). Monotone, borné, explicable.
- **Maîtrise** : un motif passe « **acquis** » si, sur les 10 dernières parties (`MASTERY_WINDOW`) écoulées
  depuis sa dernière occurrence, `n = 0` **et** ≥ 3 drills réussis (`MASTERY_DRILLS`). Un motif acquis sort du
  plan mais reste **surveillé** ; s'il réapparaît → **rechute**, réactivé avec une mention explicite.
- **Série (streak)** : nombre de jours **calendaires locaux consécutifs** avec ≥ 1 drill terminé ; repart à 0
  un jour sans drill. **Joker** algorithmique : 1 jour manqué par semaine peut être « couvert » (joker consommé),
  au plus une fois par 7 jours.

### 4.12 Déterminisme & mise à jour incrémentale
- Le Carnet est **idempotent** : réanalyser une partie **supprime puis réinsère** ses événements (clé `event_id`).
- Supprimer une partie **retire** ses événements, ses drills et recalcule les motifs (coût O(événements), négligeable).
- Aucune horloge implicite en dehors de la **date locale** ; les âges sont stockés en dates ISO.
- Deux exécutions sur les mêmes données produisent **exactement** le même carnet, le même plan, le même ordre.

### 4.13 Structures de données (persistées dans `DatabaseManager`)
```
# ── Étage 1 : CarnetEvents (sans état, sérialisable) ───────────────────────────
Atome      { event_id, game_id, ply, date_iso, couleur, polarite, categorie,
             qualite, perte_winpct, cp_loss, eval_avant, eval_apres,
             meilleur_coup, position_avant, position_apres,
             phase, eco, type_finale, regime, schemas[], tranche, dans_theorie,
             IS, IM, marqueurs[], indices[], features{ materiel, structure, criticite, ... } }

# ── Étage 2 : CarnetLedger (agrégation temporelle & multi-dimensionnelle) ──────
Motif      { famille, cle, libelle, polarite, atomes[], n, gravite_moy,
             frequence, confiance, score, tendance }
Competence { dimension, cle, skill, confiance, difficulte_moy, n,
             skill_theorie, skill_pratique, ecart, tendance }
Profil     { competences[], radar{}, indice_progression, tendance_globale,
             moments_forts[] }

# ── Étage 3 : CarnetTrainer (décision pédagogique) ─────────────────────────────
Drill      { drill_id, event_id, motif, dimension, polarite, type, position,
             reponse_uci, piege_uci, difficulte, pv[],
             srs{ EF, intervalle, repetitions, lapses, echeance }, derniere_note }
Carnet     { nb_parties, G, atomes[], faiblesses[], forces[], competences[],
             profil, drills[], maitrises[], serie, jokers, dernier_plan_date }
```

### 4.14 Constantes réglables (toutes dans un seul fichier de config)
**Négatif / agrégation** : `WINPCT_INACCURACY = 10` · `S_MAX = 40` · `DEMI_VIE_JOURS = 45` · `K_SHRINK = 4` ·
`ALPHA = 0,6` · `BETA = 0,4` · `P_MAX = 0,5` · `MIN_N_ETABLIE = 3` · `RECENT_GAMES = 20` ·
`AMELIORATION = 0,6` · `AGGRAVATION = 1,5`.

**Positif / surprise / mystère** : `ONLY_MOVE_WINPCT = 15` · `SAC_TOL_CP = 50` · `DEPTH_SHALLOW = 8` ·
`DEPTH_DEEP = 22` · `VOLATILITE_EQ_MIN = 25` · `VOLATILITE_EQ_MAX = 75` · `DEBALANCE_MAT = 2` ·
`IS_SURPRISE = 60` · `IM_MYSTERE = 65` · poids `IS` = (0,25 ; 0,20 ; 0,20 ; 0,15 ; 0,10 ; 0,10) ·
poids `IM` = (0,35 ; 0,25 ; 0,20 ; 0,20).

**Drills / plan** : `DRILLS_PER_MOTIF = 4` · `WINPCT_TOL = 3` · `SESSION_SIZE = 5` · `MAX_PER_MOTIF = 2` ·
`POSITIVE_DRILL_RATIO = 0,20` · `EF_INIT = 2,5` · `EF_MIN = 1,3` · `EF_MAX = 2,8`.

**Apprentissage (étage 3)** : `K_SKILL = 12` · `DIFFICULTE_CIBLE_MIN = 0,70` · `DIFFICULTE_CIBLE_MAX = 0,85` ·
`PLATEAU_SEANCES = 6` · `ECART_THEORIE_PRATIQUE = 8` · `MASTERY_WINDOW = 10` · `MASTERY_DRILLS = 3` ·
`JOKER_PAR_SEMAINE = 1`.

### 4.15 Cas limites & garde-fous
- **Couleur inconnue** (partie importée) : utiliser la perspective choisie par l'utilisateur ; sinon analyser les deux et étiqueter la perspective (blancs/noirs).
- **Scores de mat** : conversion cp↔win% déjà gérée en amont (`MoveQualityService`), `+M` ⇒ 100 %, `−M` ⇒ 0 %.
- **Parties trop courtes / forfaits** : ignorées (< 10 plies).
- **Moins de 5 parties** : seuls les « motifs émergents » sont montrés, aucun plan n'est imposé.
- **Positions dupliquées** : dédoublonnage des drills par `hash(position_avant + trait)` pour ne pas poser deux fois la même énigme.
- **Horloge absente** : famille « Temps » désactivée silencieusement.
- **Coup forcé** (unique légal) : écarté à la détection (A.1, condition 5).
- **Données insuffisantes pour Surprise/Mystère** : sans MultiPV (et sans passe peu profonde), `IS`/`IM` restent à **0** — **aucune surprise n'est inventée** ; un composant manquant vaut 0, jamais une valeur flatteuse par défaut.
- **Forces non affirmées sur peu de données** : une « force » suit le même seuil de confiance qu'une faiblesse (`n ≥ 3`) ; sinon elle reste un « moment fort » ponctuel.
- **Pas d'affirmation trompeuse** : un motif à faible confiance n'est jamais présenté comme une faiblesse **ni comme une force**.
- **LeArena** : les événements d'un match LLM ne sont versés au carnet du joueur que sur action explicite.

### 4.16 Exemples tracés (pour vérifier qu'on a bien compris)
**Cas négatif —** *Joueur : 25 parties aux Blancs. 9 fautes en finale (gravité moyenne pondérée 0,75), dont 6 en finale de tours.*
- Motif `(phase, finale)` : `n = 9`, `K = 9/13 = 0,69`, `P = 9/25 = 0,36`.
  `Score = 100 × 0,69 × (0,6 × 0,75 + 0,4 × min(0,36/0,5 ; 1)) = 100 × 0,69 × (0,45 + 0,288) ≈ 51`.
- Motif `(type_finale, tours)` : `n = 6`, sous-ensemble du précédent et `6 ≥ 0,5 × 9` → **retenu** ;
  `(phase, finale)` rétrogradé en « général ».
- Le motif « tours » fournit **4 drills** (les 4 fautes les plus graves) ; 2 ont une échéance aujourd'hui.
- **LePlan du jour** = ces 2 drills + 1 révision d'un autre motif + 2 drills neufs = **5 exercices**, dont
  1 seul par partie, ≤ 2 par motif. Répété demain selon les notes SM-2 → « tours » s'espace, une nouvelle
  faiblesse remonte.
- Dans 3 semaines, si `(type_finale, tours)` n'apparaît plus en partie et que ses drills sont réussis →
  marqué **acquis**, sort du plan, mais reste **surveillé** (rechute possible).

**Cas positif / curieux —** *Au 27ᵉ coup, le joueur joue un sacrifice de dame en position équilibrée
(matériel −9, mais `eval_après = +0,3`).*
- Marqueurs : `sacrifice = 1` ; `coup_unique = 1` (le 2ᵉ coup perd 22 win% > seuil 15) ; `écart_naturalité = 1`
  (coup sacrificiel, non évident) ; `volatilité` élevée (position équilibrée avant).
- `IS` dépasse 60 → double événement **`surprise` + `brillant`** ; `IM` faible (position peu ambigüe).
- **LeLive!** le commente en direct (« il donne sa dame… et c'est gagnant ! ») ; **LeCarnet** en fait un drill
  `trouve_la_brillance` et alimente la force `(schéma, sacrifice)`.

### 4.17 Bornes (ce que LeCarnet ne fait pas)
- **Aucun LLM**, aucun réseau, aucun texte inventé : uniquement des nombres, listes et positions réelles.
- **Ne nomme pas** les motifs tactiques fins (v2), **ne génère pas** de positions artificielles
  (uniquement tes positions), **ne remplace pas** l'analyse moteur (il la consomme).
- **N'exige rien** : LeCoach peut ensuite *raconter* un carnet, mais le Carnet est complet et lisible seul.
- **Ne juge pas la beauté subjective** : `IS`/`IM` sont des **proxys mesurables**, pas un goût esthétique ;
  ils peuvent manquer une beauté silencieuse (v2 : détection de motifs tactiques fins).
- **Ne décide pas du commentaire** : le seuil franchi, c'est LeLive! qui choisit ses mots — LeCarnet ne
  produit jamais de phrase.

### 4.18 Briques (par étage)
- **Réutilise** : `GameAnalyzer`, `MoveQualityService`, `OpeningBook`, `GamePhaseService`, `DatabaseManager`,
  `EngineManager` (vérification des drills + éventuelle passe peu profonde).
- **Étage 1 — `CarnetEvents`** : atomes (polarité, catégorie, `IS`, `IM`) — **réutilisé par LeLive! et LeArena**.
- **Étage 2 — `CarnetLedger`** : compilation des motifs faiblesses/forces + **compétences** par dimension + profil.
- **Étage 3 — `CarnetTrainer`** : modèle de compétence (Élo-skill), écart théorie↔pratique, scheduler,
  `DrillScheduler` (SM-2 + LePlan), détection de plateau.
- **Transverse** : `CarnetStore` (persistance), UI « LeCarnet ». **Effort 🟡** (mais **priorité n° 1**, §11).

---

## 5. Module 2 — **LeCoach** (LLM cloud / SLM local + Stockfish en outil)

> Coach conversationnel : discute d'une position, y réfléchit, vérifie **chaque** affirmation avec Stockfish,
> et parle à ton niveau. **Stockfish, pas Maia** (plus simple/rapide pour raisonner et commenter) ; Maia = jeu.

### 5.1 Boucle de tool-use (anti-hallucination)
```
Utilisateur : « Et si je sacrifiais en h7 ? »
        │
        ▼  le LLM émet un appel d'outil (jamais une affirmation non vérifiée)
┌─────────────────────────────────────────────────────────────┐
│ Outils servis par EngineManager :                            │
│  evaluate(fen, depth) · top_moves(fen, n)                    │
│  play_line(fen, moves[]) · legal_moves(fen)                  │
└─────────────────────────────────────────────────────────────┘
        │
        ▼  résultat moteur réinjecté → le LLM explique, chiffres à l'appui
```
- **Règle d'or** : aucune variation affirmée sans éval moteur.
- **Adaptation à l'Elo** (`GameAnalyzer`) : idée simple à 900, nuance stratégique à 1800.
- **Repli hors-ligne** : sans clé ni SLM, LeCarnet fournit une explication dégradée mais **vraie**.
- **Fiabiliser les petits LLM locaux** : sortie contrainte par **grammaire GBNF / `json_schema`** (llama.cpp),
  plutôt que compter sur le function-calling natif (§9). Réutilise `AICoach`, `EngineManager`. **Effort 🟡.**

---

## 6. Module 3 — **LeLive!** (commentaire LLM en direct) — **indépendant** de l'analyse moteur

| | Analyse moteur en direct (existant) | **LeLive!** (nouveau) |
| --- | --- | --- |
| Nature | calcul Stockfish continu | narration LLM |
| Sortie | barre d'éval, meilleure ligne, chiffres | phrases, explications, suspens |
| Coût | CPU local, gratuit | tokens LLM (cloud) ou SLM local |
| Rôle | vérité chiffrée | mise en récit, pédagogie, spectacle |
| Dépendance | aucune | s'appuie sur le moteur + LeCarnet (sans le remplacer) |

### 6.1 Orienté événements (indispensable coût/latence)
- **`CarnetEvents` (déterministe) annote chaque coup** : fautes (grave/modérée), **bons coups et brillances**
  (`brillant`, `trouvaille`, `précis`), **surprises** (`IS ≥ 60`) et **mystères** (`IM ≥ 65`), ainsi que les
  renversements et transitions de phase. **LeLive! ne narre que ces moments-là** — jamais tous les coups.
- **Deux vitesses** : SLM local (ligne immédiate courte) + cloud BYOK (analyse profonde).
- **File asynchrone + TTS** optionnel (coach vocal). Chaque chiffre est vérifié moteur.
- Usages : **Live** (je joue) · **Diffusion** (partie importée ou **match LeArena**).
- **Ne duplique pas la logique** : LeLive! consomme `CarnetEvents` (couche sans état, §4.0bis) et
  n'implémente pas son propre détecteur. À créer : `LiveCommentator` (narration + file + TTS) et l'UI. **Effort 🟡→🔴.**

---

## 7. Module 4 — **LeArena** (tournois LLM vs LLM) — le coup de projecteur

### 7.1 L'arbitre déterministe, jamais le LLM
```
Tour A (LLM Blanc) ──prompt: FEN + coups légaux (SAN+UCI) + PGN──► coup proposé
        │
        ▼  ChessGame : coup légal ?
        ├─ oui → appliquer, tour B
        └─ non → renvoyer l'erreur (N tentatives) ; au-delà → forfait
        │
        ▼  (option) outils Stockfish (modes assistés)
   CarnetEvents annote chaque coup (faute · brillance · surprise · mystère) → LeLive! commente → replay partageable (PGN + narration)
```
- **Anti-hallucination** : le LLM propose, `ChessGame` dispose ; jamais d'état « inventé ».
- **L'arbitre évalue pour le public, pas pour les joueurs** : en mode *Classique*, les LLM n'ont aucun accès
  moteur, mais `ArenaRunner` évalue chaque position pour alimenter `CarnetEvents` → **LeLive! commente les
  deux camps** (leurs trouvailles comme leurs gaffes), y compris **entre deux IA**.
- **Modes** : Classique (LLM seul) · Assisté (Stockfish outil) · Réflexion (reasoning/CoT) · Blitz.
- **Formats** : Exhibition 1v1 (MVP) → round-robin / bracket / suisse. **Elo interne des LLM** → leaderboard,
  alimente le `chess_rating` du catalogue (§8). Option : **tournoi quotidien** (contenu récurrent, viralité).
- **Économie** : plafond de budget, estimation via `ModelCatalog`, SLM local gratuit, cloud BYOK.
- Briques : `ChessGame`, `EngineManager`, `AICoach`, `ModelCatalog`, LeLive!, `DatabaseManager`.
  À créer : `ArenaRunner`, prompts de jeu, UI spectateur, leaderboard. **Effort 🔴 (complet) / 🟡 (1v1).**

---

## 8. Refonte du catalogue de modèles (obsolescence, Mistral, recherche/filtres)

### 8.1 Problèmes actuels
- Liste curatée **figée** → modèles obsolètes (le repo affiche des noms « v4/v5 2026 » déconnectés du marché).
- Fournisseurs manquants (dont **Mistral**), pas d'endpoint personnalisé.
- Métadonnées pauvres (pas de note d'intelligence, ni de chess-rating, ni latence, ni licence).
- `ModelHubModal` : pas de recherche/filtre/sort/comparaison ni d'estimation de coût par usage.

### 8.2 Mistral (🇫🇷 cocorico) — fournisseur à ajouter
- Provider `mistral` → `https://api.mistral.ai/v1` (compatible OpenAI), clé `api_key_mistral` (`SettingsManager`).
- Familles : Ministral, Mistral Small/Medium/Large, Magistral (raisonnement), Codestral, **Pixtral (vision →
  assistance reconnaissance d'échiquier)**, + poids ouverts exécutables via Ollama / `llama-server`.
- Arguments : hébergement **UE / RGPD** (cohérent avec l'ADN privé), bon rapport qualité/prix, poids ouverts → local.

### 8.3 Fournisseurs supplémentaires
xAI (Grok), Together, Fireworks, Cerebras, DeepInfra, Novita, Cohere, Azure OpenAI, Amazon Bedrock,
Google Vertex, + **endpoint OpenAI-compatible personnalisé** (base URL + clé + id modèle).

### 8.4 Schéma de métadonnées étendu (bump `CATALOG_SCHEMA_VERSION`)
```
provider · family · released_at · deprecation_date · is_deprecated
price_in_per_1m · price_out_per_1m · cache_price · currency · free_tier
context_length · max_output_tokens
modalities { text, vision, reasoning, audio, tools }
params_b · open_weights · license
intelligence_score · chess_rating (benchmarks LLM échecs + Elo LeArena)
speed_class · throughput
local_size_gb · quantizations · runtime (llama.cpp / ollama / cloud)
recommended_for { analyse, commentaire, commentaire-rapide, génération-de-coups }
source { curated | online | community } · last_verified
```

### 8.5 Fraîcheur (fin des modèles obsolètes)
- **Sync dynamique** par fournisseur (`/models`) : OpenRouter, Mistral, Groq, DeepSeek, Ollama…
- **Anti-obsolescence** : `is_deprecated`, masqués par défaut, « dernière synchro » + rafraîchir. Ne plus figer la liste.

### 8.6 Recherche, filtres, tri (dans `ModelHubModal`)
- **Recherche** : nom, id, famille, fournisseur. **Filtres** : fournisseur, modalité (vision/raisonnement/tools/local),
  prix, contexte, poids ouverts, installable local, chess-rating, palier d'intelligence, latence, gratuit, dépréciés.
- **Tri** : pertinence échecs, intelligence, prix, vitesse, récence, **coût estimé par partie**.
- **Presets/favoris/comparateur** · **estimateur** (analyse / partie / session LeLive! / match LeArena).

---

## 9. Inférence locale SLM — diagnostic & architecture (réponse à la question)

### 9.0 Recommandation exécutive
- **Runtime unique : `llama.cpp`** (GGUF) en sous-processus desktop, **GDExtension `.so`** sur mobile.
- **`Ollama` = passerelle optionnelle** pour utilisateurs avancés (déjà détectée) — on garde, on ne bundle pas.
- **`vLLM` = rejeté** (Python/CUDA/serveur, non embarquable dans une app desktop/mobile).
- **Format unique : GGUF**, quantization **Q4_K_M par défaut**, options IQ/Q5/Q6/Q8.
- **En Web/PWA : pas d'inférence locale** → cloud BYOK uniquement (onglet local désactivé).
- **Modèles actuels trop faibles** (SmolLM2 360M/1.7B, Qwen 0.5B) → monter d'un cran (Qwen3 4B / Gemma 3 4B / Ministral 3B).

### 9.1 Diagnostic — pourquoi « rien ne se passe »
1. **Aucun moteur d'inférence embarqué** : `bin/` ne contient que `stockfish.exe`, `lc0.exe`, `dnnl.dll` et les
   réseaux Maia — **pas de `llama-server.exe`**. `LocalSLMManager.get_server_executable_path()` ne trouve donc rien
   et `start_server_for_model()` échoue **avant même** de charger le GGUF.
2. **URL Hugging Face erronée** : le catalogue utilise `qwen2_5-0_5b-...gguf` (underscores) alors que le fichier réel
   est `qwen2.5-0.5b-instruct-q4_k_m.gguf` (points) → **404** silencieux.
3. **Échec silencieux** : `ModelHubModal._on_slm_download_failed()` **ignore `error_msg`** → l'UI se contente de
   rafraîchir ; l'utilisateur ne voit jamais la raison. `ModelDownloader` ne remonte pas de motif lisible.
4. **`HTTPRequest` + `download_file` + redirections HF (LFS/CDN)** : fragilités connues (suivi de redirection,
   `get_body_size()` à -1, progression intermittente). **Pas de reprise, pas de vérification d'intégrité (SHA256).**
5. **Plateformes** : en **PWA/WASM** et sur **Android sans `.so`**, l'inférence locale est structurellement impossible.
6. **Contexte trop court** : `-c 2048 -n 512` est insuffisant pour position + PGN + réponses d'outils LeCoach.
7. **Aucun garde-fou matériel** : rien ne vérifie RAM/VRAM ni ne recommande une quantization adaptée.

### 9.2 Choix du runtime — comparatif

| Runtime | Portable | Embarquable | GGUF | Tool-use fiable | Mobile | Web | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **llama.cpp** (`llama-server`) | ★★★★★ | ★★★★★ | ★★★★★ | ★★★★ (GBNF/json_schema) | ★★★★ (`.so`) | ★ (WASM lent) | **✅ backend unique** |
| **Ollama** | ★★★ | ✗ (démon séparé) | ★★★★★ | ★★★★ | ✗ | ✗ | ⚙️ passerelle optionnelle |
| **vLLM** | ★ | ✗ (Python/CUDA) | ✗ (GPTQ/AWQ) | ★★★★ | ✗ | ✗ | ❌ rejeté |
| MLC-LLM / WebLLM | ★★ | ★★ | ✗ | ★★★ | ★★★ | ★★★★ (WebGPU) | 🔭 piste future Web |
| llamafile | ★★★ | ★★★★ (1 fichier) | ★★★★★ | ★★★★ | ✗ | ✗ | 🔧 option packaging Windows |
| ONNX Runtime | ★★★★ | ★★★★ | ✗ (ONNX) | ★★ | ★★★★ | ★★★ | ❌ charge de conversion |
| Candle / mistral.rs (Rust) | ★★★ | ★★★ | ★★★ | ★★ | ★★ | ★★ | ❌ moins mature |

**Plus barebone ? Non.** Descendre au niveau ggml/ONNX brut, c'est beaucoup d'ingénierie pour un gain marginal :
`llama.cpp` *est* déjà la couche efficace et portable de l'écosystème ggml, avec quantization avancée et
contraintes de sortie — exactement ce dont un petit LLM-coach a besoin.

### 9.3 Formats & quantization
- **GGUF uniquement** (rejeter GPTQ/AWQ/EXL2/ONNX pour ce cas d'usage).
- **K-quants** : `Q4_K_M` = défaut (meilleur rapport qualité/taille) ; `Q5_K_M`/`Q6_K` = qualité ; `Q8_0` ≈ sans perte.
- **IQ-quants** (`IQ4_XS`, `IQ3_*`) : pour RAM très basse, qualité dégradée mais utilisable.
- **Cache KV** : viser **contexte 4096–8192** ; `--cache-type-k q8_0 --cache-type-v q8_0` et `--flash-attn` réduisent la mémoire.
- **Règle** : mémoire ≈ taille du fichier + cache KV + overhead runtime (~0,5–1 Go).

### 9.4 Quels modèles (français + raisonnement + outils)
Besoins LeCoach/LeLive! : **bon français**, **instruction-following**, **tool-use fiable**, raisonnement, taille raisonnable.

| Palier | Cible | Familles à évaluer | Taille Q4 | RAM min |
| --- | --- | --- | --- | --- |
| Léger | mobile / CPU faible | Gemma 3 1B · Qwen(2.5/3) 1.5B | ~0,8–1,1 Go | ~2 Go |
| **Standard** | desktop CPU/GPU | **Qwen3 4B** · Gemma 3 4B · Ministral 3B · Phi-4-mini | ~2,5–2,8 Go | ~5 Go |
| Qualité | GPU 8–12 Go | Qwen3 8B · Mistral Nemo 12B · Gemma 3 12B | ~5–7 Go | ~8–12 Go |
| Raisonnement | GPU / serveur | Magistral (raisonnement) · Qwen3 thinking · DeepSeek-R1-distill | variable | variable |

- **Tool-use** : Qwen et Mistral/Ministral sont les plus fiables ; **forcer la sortie par grammaire** (GBNF/`json_schema`),
  plutôt que dépendre du function-calling natif d'un modèle 1–4B.
- **Priorité française/UE** : Ministral/Mistral (cocorico), Gemma 3. **Éviter SmolLM2** (français faible, trop petit pour coacher).
- **Modèles actuels** : à retirer/reléguer ; ils ne peuvent pas tenir le rôle de coach.
- **Licences** à vérifier par famille (Apache-2.0, Gemma Terms, etc.) avant intégration.

### 9.5 Empreinte matérielle & configuration de lancement
- **CPU** : `-t` = cœurs **physiques** ; `--mlock` si RAM suffisante (évite le swap) ; sinon `--no-mmap` sur disque lent.
- **GPU** : `-ngl N` pour décharger N couches (CUDA/Vulkan/Metal) ; détecter le backend disponible et **choisir le bon build**.
- **Contextes** : mobile 2048–4096 ; desktop 4096–8192 ; `--flash-attn` + KV q8.
- **Mobile** : se limiter à 1–3B Q4, contexte 2–4k, et éventuellement **sans tool-use** (commentaire simple).
- **UI matérielle** : afficher RAM/VRAM détectées + recommandation de quantization ; avertir si insuffisant.

### 9.6 Distribution, fiabilité & plateformes
- **Manifeste de modèles vérifié** (JSON) : URL exactes (testées), `size_bytes`, **SHA256**, licence, quantization.
- **Téléchargement robuste** : suivi des redirections, **reprise**, vérification du hash, **erreur affichée** dans l'UI.
- **Runtime fourni** : bundler `llama-server` (+ dll) dans l'export desktop **ou** téléchargement in-app depuis
  `ggml-org/llama.cpp` selon OS/arch/backend ; **Android** = build `libllama.so` + JNI/GDExtension.
- **Web/PWA** : onglet local **désactivé** avec message clair (cloud BYOK), sauf piste WebGPU/WebLLM future.
- **Cycle de vie** : port occupé, arrêt propre (déjà partiellement géré), journal des erreurs visible.

### 9.7 Plan de remédiation (à implémenter plus tard)
1. Corriger les URLs du catalogue + **afficher les erreurs** de téléchargement (bug silencieux).
2. Ajouter **SHA256 + reprise** et un manifeste de modèles rafraîchissable.
3. Fournir le **runtime llama.cpp** (bundle desktop, `.so` mobile) et détecter GPU.
4. Corriger le lanceur (`-c` 4096–8192, `-ngl`, `--flash-attn`, KV q8) et exposer les erreurs.
5. **Réviser la short-list** : Qwen3 4B / Gemma 3 4B / Ministral 3B (local) + cloud pour la qualité.
6. **Tool-use contraint** (GBNF/`json_schema`) pour rendre un petit modèle exploitable par LeCoach.
7. **Gating plateforme** : désactiver proprement en Web, recommander selon RAM/VRAM.

---

## 10. La boucle de rétention « Fil Rouge »

```
1. JOUER / IMPORTER      PGN · Chess.com · vs Maia · PHOTO du plateau (OCR)
2. ANALYSE (1 clic)      Stockfish + MoveQualityService
3. LECARNET (algo)       événements (fautes, brillances, surprises, mystères) → faiblesses ET forces
4. LECOACH (LLM+moteur)  LA leçon prioritaire, au niveau du joueur, vérifiée
5. PLAN DU JOUR          drills issus de TES positions (répétition espacée)
6. PROGRESSION           score de faiblesse ↓, série, palier
   LeLive! commente · LeArena génère contenu et attention
```
**North-star metric** : *leçons complétées / faiblesses résolues* — pas « parties jouées ».

---

## 11. Priorisation

### P0 — Le wedge (**LeCarnet d'abord, priorité n° 1**)
1. **LeCarnet · Étage 1** : `CarnetEvents` — atomes par coup (polarité, catégorie, `IS`, `IM`), réutilisables en direct par LeLive!/LeArena.
2. **LeCarnet · Étage 2** : `CarnetLedger` — motifs faiblesses **et** forces, **compétences par dimension**, profil, tendances.
3. **LeCarnet · Étage 3** : `CarnetTrainer` — modèle de compétence (Élo-skill), **écart théorie↔pratique**, scheduler, `LePlan`, maîtrise.
4. **Profil de progression persistant** (Elo cumulé + delta, série) — dérivé du Carnet via `DatabaseManager`.
5. **Catalogue de modèles** : Mistral, fournisseurs additionnels, recherche/filtres/tri, fraîcheur.
6. **Confort SLM** : corriger téléchargement + erreurs, runtime llama.cpp desktop, short-list révisée.
7. **Gating Premium** : analyse illimitée, Carnet/plan avancés, SLM local.

> **Séquencement :** l'étage 1 est livrable seul (et sert déjà à LeLive!), mais **c'est l'étage 3 qui crée la rétention**.
> Les trois étages se construisent dans l'ordre, chacun **testable isolément** grâce au contrat `Atome → Compilation → Plan`.

### P1 — L'arme de différenciation
6. **LeCoach** : tool-use LLM ↔ Stockfish (contraint) + adaptation à l'Elo.
7. **LeLive!** : commentaire événementiel, Live + diffusion.
8. **Flux OTB** : photo → leçon coachée + coach vocal (TTS).
9. **LeArena (MVP)** : 1v1 arbitré + replay commenté partageable.

### P2 — Amplification
10. **LeArena tournois** : brackets/round-robin/suisse + Elo des LLM + tournoi quotidien.
11. Recherche globale, écran Statistiques, explorateur d'ouvertures, comparateur avancé.
12. **Aucune** brique réseau/social humain tant que le wedge n'est pas validé.

---

## 12. Moat, risques, garde-fous

- **Moat** : **LeCarnet** (mémoire personnelle locale, sans compte à dérober) + **LeArena** (contenu/viralité) + **model-agnostic privé**.
- **Risque n°1 — dilution** : garder l'anti-roadmap (§2).
- **Risque n°2 — qualité LLM** : sans tool-use vérifié ni adaptation au niveau, l'IA « raconte ».
- **Risque n°3 — coût LeLive!/LeArena** : plafonds de budget, narration sur événements, SLM local pour le gratuit.
- **Risque n°4 — plateformes** : SLM local inopérant en **Web/WASM** et sur **Android sans `.so`** → cloud BYOK + OCR (lui, portable) ; gating explicite.
- **Risque n°5 — modèles locaux** : trop petits = coaching médiocre → palier standard recommandé, quantization adaptée à la RAM.
- **Risque n°6 — LeArena** : coups illégaux, boucles, dépense incontrôlée → arbitre strict, tentatives bornées, budget.
- **Garde-fou** : toute feature doit répondre « quel pas du Fil Rouge améliore-t-elle ? », sinon P2.

---

## 13. Conclusion

Le mockup est une **carte des commodités** ; la valeur est ailleurs. La moitié de ses briques existe déjà,
l'autre est une course perdue contre des plateformes à effets de réseau. Le pari gagnant est la
**profondeur personnelle et l'originalité**, via une suite à responsabilités nettes :

- **LeCarnet** — la **priorité n° 1** : agrégateur déterministe en **trois étages** (atomes → compilation → renforcement), sans LLM → mémoire, compétences, rétention.
- **LeCoach** (LLM + Stockfish) → explication vérifiée, adaptée au niveau.
- **LeLive!** (LLM, événementiel) → récit et spectacle, indépendant de l'analyse moteur, branché sur l'étage 1 du Carnet.
- **LeArena** (LLM vs LLM) → contenu unique, éducatif et viral.

> **Pourquoi LeCarnet d'abord :** il est **rétentif** (mémoire personnelle), **différenciant** (théorie↔pratique,
  surprise/mystère), **offline et gratuit** (aucun token), **réutilisable** (LeLive!/LeArena consomment son étage 1),
  et il **n'existe nulle part** sous cette forme algorithmique complète. C'est le socle : tout le reste le consomme.

Côté **inférence locale**, la voie est claire : **llama.cpp + GGUF**, quantization Q4_K_M par défaut, short-list
de modèles réalistes (Qwen3 4B / Gemma 3 4B / Ministral 3B), tool-use **contraint par grammaire**, et une UI qui
**affiche enfin les erreurs** et **recommande selon RAM/VRAM**. Ollama en option, vLLM écarté, Web en cloud.

Le tout forme un écosystème **privé, offline, model-agnostic, centré sur TES parties** — qu'aucun acteur cloud
ne peut copier sans renier son modèle. Différenciant, rétentif, viral, et réalisable sans réinventer la roue.
