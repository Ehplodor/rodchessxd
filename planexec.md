# PLAN EXÉCUTIF DU PROJET : RodChessXD
> **Application mobile multi-plateforme (Godot 4.x 2D) d'analyse échiquéenne assistée par Moteurs UCI & Coach LLM/SLM**  
> *Statut : En attente de validation utilisateur (GO explicite)*  
> *Version : 1.0.0 — Date : Mars 2026*

---

## 1. VISION DU PRODUIT & OBJECTIFS

### 1.1 Proposition de valeur
**RodChessXD** est une application mobile 2D haut de gamme, fluide et autonome, conçue pour les joueurs d'échecs de tous niveaux. Elle résout la friction entre l'échiquier réel/virtuel et l'analyse approfondie :
1. **Zéro saisie manuelle fastidieuse** : importer une capture d'écran PNG (ou photo) d'un échiquier ou d'une feuille de partie pour obtenir instantanément la position FEN ou la partie PGN.
2. **Puissance brute en local** : calculs d'analyse réalisés directement sur l'appareil par les meilleurs moteurs mondiaux (Stockfish packagé, avec téléchargement direct d'autres moteurs ou réseaux spécialisés comme Maia Chess).
3. **Analyse globale pédagogique** : courbe d'évaluation dynamique, précision de jeu, détection des gaffes/coups brillants et estimation ELO réaliste.
4. **Coach IA en langage naturel** : vulgarisation et explication humaine des variantes grâce aux LLM/SLM (local sans connexion, cloud gratuit ou cloud via clé API utilisateur), alimentés par les données objectives du moteur.

---

## 2. ARCHITECTURE TECHNIQUE & CHOIX TECHNOLOGIQUES

```
+-----------------------------------------------------------------------------------+
|                                 INTERFACE GODOT 2D                                |
|   Échiquier Interactif  |  Barre & Courbe d'Éval  |  Feuille de Coups  |  Chat Coach |
+-----------------------------------------------------------------------------------+
       |                                      |                                |
+---------------+                     +-------------------+            +------------+
|  CHESS LOGIC  |                     | ENGINE CONTROLLER |            | AI COACH   |
| (Bitboard GD) |                     |  (Thread / Pipe)  |            | CONNECTOR  |
+---------------+                     +-------------------+            +------------+
       ^                                      ^                              ^
       |                                      |                              |
+---------------+                     +-------------------+            +------------+
|  CHESS OCR    |                     | STOCKFISH / MAIA  |            | LLM / SLM  |
| Vision / Grid |                     |  (GDExtension/UCI)|            | Cloud/Local|
+---------------+                     +-------------------+            +------------+
```

### 2.1 Moteur de jeu et runtime : Godot 4.x (2D)
- **Version recommandée** : Godot 4.3+ (ou 4.4).
- **Moteur de rendu** : **Compatibility (OpenGL ES 3.0)** pour mobile (Android/iOS).
  - *Justification* : Zéro stutter de compilation de shaders Vulkan sur les GPU mobiles d'entrée/milieu de gamme, consommation de batterie minimale, compatibilité maximale (99%+ des appareils Android et iPhones).
- **Résolution & Ergonomie** :
  - Mode portrait prioritaire (usage smartphone standard à une main, inspiration Chess.com/Lichess).
  - Responsive adaptatif en mode paysage ou tablette (vue scindée échiquier à gauche, graphe et coach à droite).
  - Support strict des zones d'encoche (*Safe Area*, Dynamic Island, barre de navigation système Android).

### 2.2 Gestion des plateformes mobiles (Android & iOS)
- **Contraintes de sécurité mobile critiques** :
  - *Android 10+ (W^X)* : Interdiction d'exécuter des binaires externes non signés placés dans le dossier de données de l'application (`filesDir`).
  - *iOS (App Store Guideline 2.5.2)* : Interdiction formelle de lancer des sous-processus via `fork()` / `exec()`.
- **Solution architecturale adoptée** :
  - Intégration du moteur via **GDExtension (C++)** ou compilation native partagée (`.so` sur Android, `.dylib` / framework sur iOS, `.dll` sur Windows).
  - Le moteur Stockfish tourne dans un **thread C++ natif en mémoire** au sein de l'application, communiquant avec GDScript via une file de messages asynchrone non-bloquante au standard UCI.
  - Cette approche garantit la compatibilité 100% App Store et Google Play Store sans bidouillage de sous-processus.

---

## 3. ÉTUDE DÉTAILLÉE PAR MODULE

### MODULE 1 : Moteur de Règles & Modèle de Données (Core Chess)
- **Composant** : `ChessCore` (GDScript + structures optimisées).
- **Représentation** :
  - Représentation hybride Mailbox (tableau 64 cases) pour affichage et Bitboards (64-bit integers) pour la génération ultra-rapide des coups légaux, échecs, pats, roques, prises en passant et règle des 50 coups.
- **Support I/O** :
  - **FEN** (Forsyth-Edwards Notation) : lecture et écriture complètes avec statut de roque, en-passant, demi-coups.
  - **PGN** (Portable Game Notation) : parseur robuste supportant les métadonnées (Event, Site, Date, White, Black, Result), les coups au format SAN, les annotations NAGs ($1 pour `!`, $2 pour `?`, $4 pour `??`), et les variantes imbriquées.

---

### MODULE 2 : Système d'Import PNG & Reconnaissance (Chess OCR)

L'import d'une image doit répondre à deux besoins : une **position unique** (capture d'échiquier) ou une **partie complète** (feuille de coups PGN ou historique).

```
                      [ Fichier PNG sélectionné ]
                                  |
               +------------------+------------------+
               |                                     |
    [ Capture d'Échiquier ]              [ Feuille de partie / PGN ]
               |                                     |
    Détection des 4 coins                 Vision Multimodale Cloud
    & Découpage 64 cases                  (Gemini / GPT / Claude)
               |                                     |
    Classification des pièces             Extraction texte PGN
    (Modèle compact / CNN)                           |
               |                                     |
               +------------------+------------------+
                                  |
                     [ Écran de validation FEN/PGN ]
                     (Correction manuelle si besoin)
                                  |
                      [ Validation -> Analyse ]
```

1. **Phase 1 : Sélection & Prétraitement de l'image** :
   - Sélecteur de fichiers natif (Galerie mobile ou explorateur).
   - Détection automatique de la zone d'échiquier :
     - Recherche de la grille carrée par analyse de contours/gradients de contraste.
     - Redressement de perspective (transformation homographique).
   - Sécurité ergonomique : Assistant de recadrage manuel si la détection automatique hésite (l'utilisateur ajuste les 4 coins et sélectionne la couleur en bas : Blancs ou Noirs).
2. **Phase 2 : Reconnaissance des 64 cases (Tier Double)** :
   - **Tier A (100% Hors-ligne / Local)** :
     - Modèle de classification CNN ultra-léger (13 classes : Case vide, 6 pièces blanches, 6 pièces noires).
     - Validation algorithmique de la légalité échiquéenne (exactement 1 roi blanc, 1 roi noir, aucun pion sur les rangées 1 et 8, nombre de pièces <= 16 par camp).
   - **Tier B (Cloud Vision / Multimodal)** :
     - Pour les feuilles de partie manuscrites/imprimées ou les diagrammes complexes : envoi au LLM Vision (Gemini Flash gratuit ou API utilisateur) avec un prompt JSON strict pour extraire le PGN ou le FEN.
3. **Phase 3 : Écran d'Ajustement & Validation Utilisateur** :
   - Affichage côte à côte : Image originale vs Échiquier numérique reconstitué.
   - Palette d'édition rapide : permet de glisser-déposer ou modifier en 1 clic une case mal reconnue avant de lancer l'analyse.
   - Sélection du trait (Trait aux Blancs / Trait aux Noirs) et des droits au roque.

---

### MODULE 3 : Moteurs d'Échecs & Système de Téléchargement

1. **Moteur Packagé par défaut (Out-of-the-Box)** :
   - **Stockfish 17 (Build Lite Embedded)** :
     - Intégré directement dans l'application avec un réseau neuronal NNUE compact (~6 à 10 Mo).
     - Prêt à l'emploi dès l'installation, sans nécessiter de connexion internet.
2. **Gestionnaire de Téléchargement Intégré (Engine Hub)** :
   - Interface dédiée permettant de télécharger en direct depuis l'application :
     - **Réseau NNUE Large de Stockfish** (~45 Mo) : pour une précision grand-maître maximale.
     - **Maia Chess (1100, 1500, 1900 ELO)** :
       - *Intérêt majeur* : Maia est entraîné pour prédire les coups joués par des *humains* d'un niveau donné, et non le coup parfait d'une machine. Cela permet une détection incomparable des erreurs typiques humaines et une estimation ELO sur-mesure.
     - **Moteurs alternatifs légers** (ex. Arasan, Ethereal) pour les appareils très peu puissants.
   - Fonctions du gestionnaire : barre de progression, reprise sur erreur, vérification de somme MD5/SHA256, gestion de l'espace disque (suppression en 1 clic).
3. **Contrôleur UCI Asynchrone** :
   - Communication bidirectionnelle standardisée (`uci`, `isready`, `position fen ... moves ...`, `go depth X movetime Y`, `stop`).
   - Parsing en temps réel des lignes `info depth ... score cp ... mate ... pv ... nps ...`.
   - Paramétrage utilisateur :
     - Nombre de cœurs CPU alloués (1 à 4 pour mobile afin d'éviter la surchauffe et la baisse de batterie).
     - Mémoire table de hachage (Hash : 16 Mo à 256 Mo).
     - Profondeur d'analyse cible (ex. 18 demi-coups pour analyse rapide, 24+ pour analyse profonde).
     - MultiPV (analyse simultanée des 2 ou 3 meilleures alternatives).

---

### MODULE 4 : Moteur d'Analyse Globale & Métriques Avancées

1. **Pipeline d'analyse coup par coup** :
   - Pour chaque coup joué, le moteur évalue :
     - Le score de la position avant le coup ($S_{avant}$).
     - Le score après le coup ($S_{après}$).
     - Le meilleur coup possible ($PV_1$) et son score.
     - La perte en centipions : $CPL = \max(0, S_{best} - S_{played})$.
2. **Classification qualitative des coups** (standard international) :
   - **Brillant (`!!`)** : Coup impliquant un sacrifice de matériel matériellement gagnant ou maintenant un avantage décisif, difficile à trouver.
   - **Formidable / Grand coup (`!`)** : Coup critique unique maintenant la victoire ou sauvant la nullité.
   - **Meilleur coup** : Choix n°1 de l'ordinateur.
   - **Excellent** : Perte < 15 centipions.
   - **Bon** : Perte entre 15 et 35 centipions.
   - **Imprécision (`?!`)** : Perte entre 35 et 90 centipions.
   - **Erreur (`?`)** : Perte entre 90 et 200 centipions.
   - **Gaffe (`??`)** : Perte > 200 centipions ou coup faisant basculer une position gagnante en position perdante.
   - **Occasion manquée** : Manquer une gaffe adverse ou un gain immédiat.
3. **Courbe d'Avantage Dynamique (Graphe 2D interactif)** :
   - Tracé vectoriel continu lissé de l'évaluation (-10 à +10, avec plafond de mat).
   - Remplissage en dégradé bicolore (Blanc en haut, Noir en bas).
   - Points d'impact cliquables : pastilles colorées sur les gaffes, erreurs et coups brillants.
   - Défilement tactile (*scrubbing*) : faire glisser le doigt sur la courbe met à jour instantanément l'échiquier sur la position correspondante.
4. **Précision & Estimation ELO des Joueurs** :
   - **Score de précision (CAPS / Win-Chance Model)** :
     - Formule basée sur la probabilité de gain : $P(gain) = \frac{1}{1 + 10^{-cp / 400}}$.
     - Calcul du pourcentage de précision de 0% à 100% pour les Blancs et les Noirs.
   - **Estimation ELO** :
     - Modèle statistique croisant :
       1. La perte moyenne en centipions (ACPL).
       2. La fréquence des erreurs/gaffes par rapport au nombre total de coups.
       3. La performance par phase de jeu (Ouverture, Milieu de jeu, Finale).
       4. La corrélation avec les prédictions Maia Chess (si disponible).
     - Restitution sous forme d'intervalle de confiance (ex. "Blancs : 1650 ± 75 ELO | Noirs : 1420 ± 90 ELO").

---

### MODULE 5 : Intégration LLM & Coach Virtuel en Langage Naturel

Le point fort de RodChessXD est de traduire les chiffres bruts d'un moteur (+2.4, CPL 140) en **explications stratégiques et tactiques intelligibles**.

```
+-------------------------------------------------------------------------------+
|                             GÉNÉRATEUR DE CONTEXTE                            |
| FEN actuel | Coup joué | Perte CP | Top 3 Moteur (PV) | Motifs tactiques | PGN|
+-------------------------------------------------------------------------------+
                                       |
                   +-------------------+-------------------+
                   |                   |                   |
            [ Tier 1 : SLM ]    [ Tier 2 : Cloud ]  [ Tier 3 : API ]
             Local Embarqué        Gratuit Clé       Propriétaire
            (GGUF / On-Device)   (Gemini / Groq)   (OpenAI / Claude /
                                                    DeepSeek R1)
                   |                   |                   |
                   +-------------------+-------------------+
                                       |
+-------------------------------------------------------------------------------+
|                               RÉPONSE DU COACH                                |
|  "Ce coup est une gaffe car il abandonne le contrôle de la case d5,           |
|   permettant à votre adversaire d'installer une fourchette de cavalier..."    |
+-------------------------------------------------------------------------------+
```

1. **Les 3 Tiers d'IA supportés** :
   - **Tier 1 : SLM Local (Small Language Model - 100% Hors-ligne & Gratuit)** :
     - Modèles compacts quantifiés (1B à 2B paramètres, format GGUF ou ONNX, ex. *SmolLM2-1.7B-Instruct*, *Qwen2.5-1.5B*, *Gemma-2-2B*).
     - Exécuté via un runtime inférence C++ embarqué (llama.cpp wrapper en GDExtension).
     - Garantit le fonctionnement dans un avion ou sans aucun réseau.
   - **Tier 2 : LLM Cloud Gratuit (Sans configuration complexe)** :
     - Support des offres sans frais :
       - **Google Gemini API (Free tier)** : quota de requêtes gratuit très rapide avec Gemini 2.0 Flash.
       - **Groq Cloud API** : accès haute vitesse gratuit (Llama 3.3 70B / 8B).
       - **OpenRouter Free Tier**.
   - **Tier 3 : LLM Cloud avec clé API personnelle (BYOK - Bring Your Own Key)** :
     - Support des modèles de pointe : OpenAI (GPT-4o / GPT-4o-mini), Anthropic (Claude 3.5 Sonnet / Haiku), DeepSeek (DeepSeek-V3 et DeepSeek-R1 spécialisé dans le raisonnement profond), Mistral AI.
     - Sauvegarde sécurisée et chiffrée de la clé API dans le stockage local sécurisé de l'appareil (`user://credentials.cfg`).
2. **Construction du Prompt Hybride (Anti-Hallucination)** :
   - Les LLM échouent souvent aux échecs s'ils doivent calculer seuls. RodChessXD supprime les hallucinations en fournissant **la solution calculée par Stockfish** dans le prompt :
     ```json
     {
       "position_fen": "...",
       "coup_joue": "Fe6?",
       "evaluation": "-1.8 (Erreur, perte de 190 centipions)",
       "meilleur_coup_moteur": "Te8 (+0.1)",
       "ligne_tactique_refutation": ["1... Fe6?", "2. Cg5! Fg8", "3. Cxe6 fxe6", "4. Dxe6+"],
       "motifs_detectes": ["Fourchette", "Pièce non protégée", "Roi affaibli"],
       "profil_joueur": "Niveau 1300 ELO, cherche explications conceptuelles"
     }
     ```
3. **Fonctionnalités du Coach dans l'Interface** :
   - **Mode "Pourquoi ce coup est mauvais ?"** : explication claire du piège ou de la menace manquée.
   - **Mode "Quel était le plan ?"** : explication stratégique (colonnes ouvertes, avant-postes, structure de pions).
   - **Mode "Coach Interactif"** : champ de chat permettant au joueur de poser n'importe quelle question sur la position en cours.
   - **Personnalités de coach** : sélectionnable dans les réglages (Bienveillant, Grand-Maître rigoureux, Pédagogue pour enfants).

---

### MODULE 6 : Interface Graphique & Expérience Mobile (UI/UX 2D)

- **Thème Visuel** : Esthétique moderne et épurée (Dark Mode profond, surfaces verre/glassmorphism subtil, animations fluides à 60/120 fps).
- **Composants d'affichage** :
  1. **Échiquier 2D** :
     - Déplacement fluide par glisser-déposer (*drag & drop*) ou clic-puis-clic (*tap-to-move*).
     - Mise en surbrillance : dernier coup joué, cases de destination légales (points doux), menaces et échecs (lueur rouge).
     - Flèches d'analyse dynamiques : flèche verte pour le meilleur coup moteur, flèche rouge/orange pour les erreurs.
     - Personnalisation : thèmes de pièces (Neo, Classic, Wood, Minimalist) et d'échiquier.
  2. **Barre d'Évaluation Verticale** :
     - Animation élastique du score (+1.5, -0.8) avec ratio visuel Blanc/Noir en direct.
  3. **Feuille de Coups Interactive** :
     - Liste défilante des coups avec pastilles d'analyse (vert, bleu, jaune, rouge).
     - Raccourcis de navigation : Boutons Début, Coup Précédent, Pause/Lecture automatique, Coup Suivant, Fin.
  4. **Tiroir / Panneau d'Analyse & Coach** :
     - Onglets : *Moteur brut* (variantes détaillées, profondeur, nœuds/s), *Bilan de partie* (précision, gaffes, ELO), *Coach IA* (dialogue explicatif).

---

## 4. FEUILLE DE ROUTE D'EXÉCUTION (PHASAGE ÉTAPE PAR ÉTAPE)

```
[ Phase 0 : Initialisation ]
             |
[ Phase 1 : Core Chess & Échiquier 2D ]
             |
[ Phase 2 : Moteur UCI & Intégration Stockfish ]
             |
[ Phase 3 : Module d'Import & OCR Échiquier ]
             |
[ Phase 4 : Analyse Complète, Graphe & Métriques ELO ]
             |
[ Phase 5 : Intégration Coach IA (SLM/LLM) ]
             |
[ Phase 6 : Finitions, UI Polish & Packaging Mobile ]
```

### Phase 0 : Fondations du Projet & Architecture Godot
- Création du projet Godot 4.x configuré pour Mobile (Compatibility Renderer, viewport portrait, stretch mode `canvas_items`).
- Mise en place de l'arborescence standardisée :
  - `res://src/core/` (Logique échiquéenne, FEN, PGN)
  - `res://src/engine/` (Gestionnaire UCI, wrappers Stockfish)
  - `res://src/vision/` (OCR, traitement d'image, reconnaissance)
  - `res://src/ai/` (Connecteurs LLM, SLM local, gestion des clés)
  - `res://src/ui/` (Composants 2D, thèmes, échiquier, graphe)
  - `res://assets/` (Textures pièces, sons, polices Google Inter/Outfit)
- Configuration de la gestion d'état globale (`GameController.gd`, `SettingsManager.gd`).

### Phase 1 : Cœur Échiquéen & Échiquier Tactile 2D
- Implémentation du générateur de règles, déplacements légaux et détection d'état (échec, mat, pat).
- Implémentation du parseur/sérialiseur FEN et PGN.
- Création du composant d'échiquier 2D responsive :
  - Déplacement tactile fluide, prévisualisation des coups, sons de déplacement et de prise.
  - Historique de navigation coup par coup.

### Phase 2 : Intégration Stockfish & Pipeline Asynchrone
- Mise en place du module C++ / GDExtension ou binaire natif multi-plateforme pour Stockfish.
- Création du contrôleur UCI asynchrone en arrière-plan (non-blocage des 60 fps du jeu).
- Évaluation en temps réel d'une position statique (score, profondeur, meilleure ligne PV).
- Écran de téléchargement de moteurs/réseaux supplémentaires (Maia, Stockfish large NNUE) avec gestionnaire HTTP et stockage dans `user://engines/`.

### Phase 3 : Module d'Import PNG & Chess OCR
- Intégration du sélecteur d'image natif.
- Pipeline de détection de grille 8x8 et recadrage d'échiquier.
- Algorithme de reconnaissance des pièces sur les 64 cases (modèle local + fallback vision cloud).
- Création de l'interface de validation/correction utilisateur avant injection dans l'analyseur.

### Phase 4 : Analyse Globale de Partie, Courbe d'Avantage & ELO
- Boucle d'analyse complète automatique sur une liste de coups PGN.
- Algorithme de calcul d'ACPL (perte moyenne en centipions) et catégorisation des coups (`!!`, `!`, `?`, `??`).
- Développement du composant 2D personnalisé de courbe d'évaluation (Line2D avec gradients, points d'inflexion cliquables et scrubbing tactile).
- Formule mathématique d'estimation ELO basée sur les métriques de partie.

### Phase 5 : Module IA Coach (SLM Local + Cloud Gratuit + Clés API)
- Connecteur API REST HTTP vers les fournisseurs Cloud (OpenAI, Gemini, Anthropic, Groq, OpenRouter).
- Intégration du connecteur SLM local (runtime compact GGUF/llama.cpp en GDExtension).
- Système de templates de prompts contextuels injectant les métriques Stockfish.
- Interface UI du Coach : chat conversationnel, infobulles explicatives et explications audio/texte.

### Phase 6 : Optimisations Mobiles, Polish UI & Tests d'Acceptation
- Application du design system (glassmorphism, micro-animations, thèmes sombre/clair).
- Gestion fine de la mémoire vive et de l'énergie (mise en veille du moteur si l'application passe en arrière-plan).
- Tests sur Android (APK/AAB) et préparation iOS (Export Xcode).
- Documentation utilisateur et guide de prise en main.

---

## 5. MATRICE DES RISQUES TECHNIQUES & SOLUTIONS

| Risque identifié | Niveau | Impact | Solution technique validée |
| :--- | :---: | :---: | :--- |
| **Sécurité Android (W^X)** | Élevé | Binaire externe bloqué | Stockfish compilé en bibliothèque native partagée via GDExtension C++. |
| **Sandbox iOS (Pas de fork/exec)** | Élevé | Rejet App Store | Stockfish lié en bibliothèque interne tournant dans un thread C++ de l'app. |
| **Surchauffe / Batterie Mobile** | Moyen | Mauvaise expérience | Limitation par défaut à 2 threads CPU et extinction du moteur en veille. |
| **Erreurs de reconnaissance OCR** | Moyen | FEN incorrect | Écran d'ajustement interactif obligatoire avec palette de correction rapide. |
| **Hallucinations du LLM** | Élevé | Mauvais conseils | Le LLM ne calcule rien : les variantes et évaluations de Stockfish lui sont fournies. |
| **Taille du SLM local sur mobile** | Moyen | Poids de l'APK | Téléchargement optionnel à la demande du modèle SLM (non imposé dans l'APK de base). |

---

## 6. CRITÈRES DE VALIDATION & CONDITIONS DU "GO"

Avant d'écrire la moindre ligne de code, les décisions suivantes sont soumises à votre validation :
1. **Validation du périmètre** : Confirmez-vous le phasage de Phase 0 à Phase 6 ?
2. **Priorité initiale de l'OCR** : Souhaitez-vous privilégier d'abord les captures d'écran numériques d'échiquiers (Chess.com / Lichess) avant les photos d'échiquiers réels en bois avec perspective ?
3. **Moteur embarqué initial** : Êtes-vous d'accord pour embarquer Stockfish Lite par défaut et proposer Maia / Stockfish Full en téléchargement in-app ?
4. **Modèle de SLM local** : Êtes-vous d'accord pour que le modèle local (SLM) soit proposé en téléchargement additionnel (pour garder un APK léger de ~30-50 Mo au départ) ?

> **RAPPEL FORMEL** : Conformément à votre consigne, **AUCUN CODE NE SERA ÉCRIT** tant que vous n'aurez pas donné votre **GO EXPLICITE** sur ce plan et ses éventuels ajustements.
